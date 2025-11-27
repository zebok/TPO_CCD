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


# --- Predicción para N pacientes (robusto a formatos de ranger) -------

N <- 5

# Opción A: manual (pone índices del TEST que quieras)
# pac_idx <- c(1, 2, 3, 4, 5)

# Opción B: automática (extremos + mediano según riesgo del TEST)
#  - usa 'risk_score' calculado antes para TODO el test
orden <- order(risk_score, decreasing = TRUE)
med  <- orden[round(length(orden) / 2)]
pac_idx <- unique(c(orden[1:2], med, tail(orden, 2)))[1:N]

stopifnot(all(pac_idx >= 1 & pac_idx <= nrow(df_te)))

df_sel  <- df_te[pac_idx, , drop = FALSE]
pred_sel <- predict(rsf, data = df_sel, type = "response")

# Tiempos únicos del bosque
times <- pred_sel$unique.death.times
if (is.null(times)) times <- pred_te$unique.death.times

# CHF y S(t) según devuelva ranger
if (!is.null(pred_sel$chf)) {
  CHF_mat <- if (is.matrix(pred_sel$chf)) pred_sel$chf else do.call(rbind, pred_sel$chf)
  S_mat   <- exp(-CHF_mat)
} else if (!is.null(pred_sel$survival)) {
  S_mat   <- if (is.matrix(pred_sel$survival)) pred_sel$survival else do.call(rbind, pred_sel$survival)
  S_mat   <- pmax(S_mat, 1e-12)
  CHF_mat <- -log(S_mat)
} else {
  stop("La predicción de ranger no trae 'chf' ni 'survival'.")
}

# Horizontes
t3y <- 365 * 3; t5y <- 365 * 5
k3  <- findInterval(t3y, times, all.inside = TRUE)
k5  <- findInterval(t5y, times, all.inside = TRUE)

# Risk score y mediana
risk_sel <- apply(CHF_mat, 1, \(x) tail(x, 1))
mediana_fun <- function(s, tt) { idx <- which(s <= 0.5)[1]; if (is.na(idx)) NA_real_ else tt[idx] }

res_pacientes <- tibble::tibble(
  fila_test          = pac_idx,
  risk_score         = risk_sel,
  S_3_anios          = S_mat[, k3],
  S_5_anios          = S_mat[, k5],
  P_evento_3_anios   = 1 - S_mat[, k3],
  P_evento_5_anios   = 1 - S_mat[, k5],
  mediana_superviv_d = apply(S_mat, 1, mediana_fun, tt = times)
) |>
  dplyr::arrange(desc(risk_score))

cat("\n=== Predicciones por paciente (filas de TEST) ===\n")
print(res_pacientes, n = Inf)

# --- Curvas S(t) para los N pacientes ---------------------------------
df_curvas <- purrr::map_dfr(seq_len(nrow(S_mat)), function(i) {
  tibble::tibble(
    paciente = paste0("Paciente test #", res_pacientes$fila_test[i]),
    tiempo   = times,
    S        = S_mat[match(res_pacientes$fila_test[i], pac_idx), ]
  )
})

ggplot2::ggplot(df_curvas, ggplot2::aes(x = tiempo, y = S, color = paciente)) +
  ggplot2::geom_line(size = 1) +
  ggplot2::geom_vline(xintercept = c(t3y, t5y), linetype = "dashed") +
  ggplot2::coord_cartesian(xlim = c(0, 365*10)) +  # <-- 10 años en días
  ggplot2::scale_x_continuous(breaks = 0:(10) * 365, labels = 0:10)
  ggplot2::labs(title = paste0("Curvas de supervivencia (RSF) - ", N, " pacientes de test"),
                x = "Días", y = "S(t)") +
  ggplot2::theme_minimal()



# --- Variables de esos pacientes (tabla detallada) --------------------
# Traer id del TEST si existe
if ("id_paciente" %in% names(datos_clean)) {
  id_te <- datos_clean$id_paciente[-idx_tr]
} else {
  id_te <- seq_len(nrow(df_te))
}

df_sel_print <- df_sel |> dplyr::mutate(across(where(is.factor), as.character))

meta_sel <- tibble::tibble(
  fila_test   = pac_idx,
  id_paciente = id_te[pac_idx],
  tiempo_real = t_te[pac_idx],
  evento_real = e_te[pac_idx]
)

for (i in seq_along(pac_idx)) {
  cat("\n------------------------------\n")
  cat("Paciente TEST #", pac_idx[i],
      "  (ID: ", meta_sel$id_paciente[i], ")",
      "\nTiempo real: ", meta_sel$tiempo_real[i],
      "  |  Evento real: ", meta_sel$evento_real[i], "\n", sep = "")
  
  tibble::tibble(
    variable = names(df_sel_print),
    valor    = as.character(df_sel_print[i, ] |> unlist(use.names = FALSE))
  ) |>
    dplyr::arrange(variable) |>
    print(n = Inf)
}

# (Opcional) tabla ancha comparativa
tabla_ancha <- df_sel_print |>
  tibble::rowid_to_column("pos_en_seleccion") |>
  dplyr::mutate(
    fila_test   = pac_idx,
    id_paciente = id_te[pac_idx],
    tiempo_real = t_te[pac_idx],
    evento_real = e_te[pac_idx]
  ) |>
  dplyr::relocate(fila_test, id_paciente, tiempo_real, evento_real, pos_en_seleccion)

cat("\nResumen ancho de los", N, "pacientes:\n")
print(tabla_ancha)
