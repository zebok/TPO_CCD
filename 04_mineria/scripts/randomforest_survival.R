# ============================================================================
# RANDOM SURVIVAL FOREST (RSF) - Supervivencia con censura (ranger)
# ============================================================================
# - Maneja censura correctamente (a diferencia de una regresión MSE).
# - Incluye: limpieza/imputación, partición estratificada, RSF, C-index,
#   estratos de riesgo (terciles) + Log-rank, e importancia de variables.
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(caret)
library(survival)
library(forcats)
library(ranger)      # RSF
library(dplyr)
# --- 0. UTILIDADES ---
align_factor_levels <- function(train_df, test_df) {
  # Asegura que train y test tengan los mismos niveles de factor
  fac_cols <- names(train_df)[sapply(train_df, is.factor)]
  for (col in fac_cols) {
    lvls <- union(levels(train_df[[col]]), levels(test_df[[col]]))
    train_df[[col]] <- forcats::fct_expand(train_df[[col]], lvls)
    test_df[[col]]  <- forcats::fct_expand(test_df[[col]],  lvls)
  }
  list(train = train_df, test = test_df)
}

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- readr::read_csv(dataset_path)

cat("Dataset:", nrow(datos), "filas y", ncol(datos), "columnas\n")

# Codificar evento: 1 = DECEASED, 0 = LIVING
datos <- datos %>%
  mutate(survival_event_numeric = case_when(
    survival_event == "DECEASED" ~ 1,
    survival_event == "LIVING"   ~ 0,
    TRUE ~ NA_real_
  ))

# Filtrar filas con tiempo y evento definidos
datos_clean <- datos %>%
  filter(!is.na(overall_survival), !is.na(survival_event_numeric))

time  <- datos_clean$overall_survival
event <- datos_clean$survival_event_numeric

# --- 2. SELECCIÓN DE FEATURES (igual que tu pipeline sin genes) ---
genes_excluir <- c(
  "esr1_expression","pgr_expression","erbb2_expression","mki67_expression",
  "tp53_expression","brca1_expression","brca2_expression","pik3ca_expression",
  "pten_expression","akt1_expression"
)

variables_a_eliminar <- c(
  "id_paciente","dataset_source",
  "overall_survival","survival_event","survival_event_numeric","vital_status",
  genes_excluir,"diagnosis"
)

predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

# --- 3. PARTICIÓN TRAIN/TEST ESTRATIFICADA POR EVENTO ---
set.seed(123)
idx_tr <- createDataPartition(event, p = 0.8, list = FALSE)
X_tr <- predictores[idx_tr, , drop = FALSE]
X_te <- predictores[-idx_tr, , drop = FALSE]
t_tr <- time[idx_tr]; t_te <- time[-idx_tr]
e_tr <- event[idx_tr]; e_te <- event[-idx_tr]

cat("Train:", nrow(X_tr), "| Test:", nrow(X_te), "\n")

# --- 4. LIMPIEZA / IMPUTACIÓN (SIN NAs) ---

# 4.1 pasar strings vacíos a NA
X_tr <- X_tr %>% mutate(across(where(is.character), ~na_if(., "")))
X_te <- X_te %>% mutate(across(where(is.character), ~na_if(., "")))

# 4.2 convertir character -> factor
X_tr <- X_tr %>% mutate(across(where(is.character), as.factor))
X_te <- X_te %>% mutate(across(where(is.character), as.factor))

# 4.3 imputación
#     - numéricos: mediana del TRAIN
#     - factores: nivel explícito "Missing"
num_cols_tr <- names(X_tr)[sapply(X_tr, is.numeric)]
medianas <- X_tr %>% summarise(across(all_of(num_cols_tr), ~median(., na.rm = TRUE)))

for (nm in names(medianas)) {
  X_tr[[nm]][is.na(X_tr[[nm]])] <- medianas[[nm]]
  if (nm %in% names(X_te)) {
    X_te[[nm]][is.na(X_te[[nm]])] <- medianas[[nm]]
  }
}

X_tr <- X_tr %>% mutate(across(where(is.factor), ~fct_explicit_na(., na_level = "Missing")))
X_te <- X_te %>% mutate(across(where(is.factor), ~fct_explicit_na(., na_level = "Missing")))

# 4.4 columnas sin variación -> eliminar
keep <- sapply(X_tr, function(x) if (is.factor(x)) nlevels(x) >= 2 else length(unique(x)) >= 2)
X_tr <- X_tr[, keep, drop = FALSE]
X_te <- X_te[, keep, drop = FALSE]

# 4.5 alinear niveles de factores entre train y test
aligned <- align_factor_levels(X_tr, X_te)
X_tr <- aligned$train; X_te <- aligned$test

# 4.6 chequeo final de NAs
stopifnot(!any(sapply(X_tr, anyNA)))
stopifnot(!any(sapply(X_te, anyNA)))

# --- 5. ENTRENAR RSF (ranger) ---
df_tr <- X_tr %>% mutate(.time = t_tr, .status = e_tr)
df_te <- X_te %>% mutate(.time = t_te, .status = e_te)

set.seed(123)
rsf <- ranger(
  formula       = Surv(.time, .status) ~ .,
  data          = df_tr,
  num.trees     = 1000,
  mtry          = floor(sqrt(ncol(X_tr))),  # probar sqrt(p), p/3, p/2
  min.node.size = 15,                       # 5–30 (tuning fino)
  splitrule     = "logrank",                # o "extratrees"
  importance    = "permutation",
  oob.error     = TRUE
)

print(rsf)

# --- 6. PREDICCIÓN Y MÉTRICAS ---
# Para RSF usamos el "riesgo" = hazard acumulado final (mayor = peor)
pred_te <- predict(rsf, data = df_te, type = "response")
risk_score <- sapply(seq_len(nrow(df_te)), function(i) tail(pred_te$chf[[i]], 1))

# C-index (Harrell) — >0.60 empieza a ser útil; 0.5 ≈ azar
cidx <- survConcordance(Surv(t_te, e_te) ~ risk_score)
cat("C-index (test):", round(cidx$concordance, 3), "\n")

# --- 7. ESTRATOS DE RIESGO + LOG-RANK ---
df_eval <- tibble(
  tiempo = t_te,
  evento = e_te,
  riesgo = risk_score
) %>%
  mutate(
    # ntile crea terciles aun con empates
    tercil = ntile(riesgo, 3),
    # ¡OJO! mayor "riesgo" (CHF) = peor pronóstico
    grupo_riesgo = factor(case_when(
      tercil == 1 ~ "Bajo",
      tercil == 2 ~ "Medio",
      tercil == 3 ~ "Alto"
    ), levels = c("Bajo","Medio","Alto"))
  )

print(survdiff(Surv(tiempo, evento) ~ grupo_riesgo, data = df_eval))  # test de log-rank

# (Si usás survminer)
# library(survminer)
# ggsurvplot(survfit(Surv(tiempo, evento) ~ grupo_riesgo, data = df_eval),
#            risk.table = TRUE, pval = TRUE, palette = c("#1a9850","#fee08b","#d73027"))

# --- 8. IMPORTANCIA DE VARIABLES ---
imp <- sort(importance(rsf), decreasing = TRUE)
cat("Top 20 features por importancia (permutation):\n")
print(head(imp, 20))

# --- 9. (OPCIONAL) PEQUEÑO TUNING GRID POR C-INDEX ---
# set.seed(123)
# grid <- expand.grid(
#   mtry = c(floor(sqrt(ncol(X_tr))), floor(ncol(X_tr)/3)),
#   min.node.size = c(5, 15, 30),
#   splitrule = c("logrank","extratrees")
# )
# res <- pmap_dfr(grid, function(mtry, min.node.size, splitrule){
#   fit <- ranger(Surv(.time, .status) ~ ., data = df_tr,
#                 num.trees=1000, mtry=mtry, min.node.size=min.node.size,
#                 splitrule=splitrule)
#   pr  <- predict(fit, data = df_te, type = "response")
#   risk <- sapply(seq_len(nrow(df_te)), function(i) tail(pr$chf[[i]],1))
#   cdx <- survConcordance(Surv(t_te, e_te) ~ risk)
#   tibble(mtry=mtry, min.node.size=min.node.size, splitrule=splitrule,
#          cindex=cdx$concordance)
# })
# arrange(res, desc(cindex))
