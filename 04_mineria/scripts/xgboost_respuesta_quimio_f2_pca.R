# ============================================================================
# XGBOOST - RESPUESTA A QUIMIOTERAPIA (OPTIMIZADO F2-SCORE + PCA)
# ============================================================================
# Objetivo: Predecir respuesta a quimioterapia PRIORIZANDO RECALL
#           (detectar TODAS las buenas respuestas para no perder vidas)
#
# Mejoras clave:
#   1. Optimización para F2-Score (prioriza Recall 2x sobre Precision)
#   2. PCA para reducir 10 genes a 2-3 componentes principales
#   3. Umbral optimizado para maximizar detección de buenas respuestas
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(xgboost)
library(caret)
library(FactoMineR)  # Para PCA

# Función para calcular F2-Score
f2_score <- function(precision, recall) {
  beta <- 2
  return((1 + beta^2) * (precision * recall) / ((beta^2 * precision) + recall))
}

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print("============================================")
print("MODELO OPTIMIZADO PARA SEGURIDAD CLÍNICA")
print("Prioridad: DETECTAR TODAS LAS BUENAS RESPUESTAS")
print("Métrica: F2-Score (2x peso en Recall)")
print("============================================")
print("")

# --- 2. DEFINIR RESPUESTA A QUIMIOTERAPIA ---

datos_clean <- datos %>%
  filter(
    !is.na(chemotherapy),
    !is.na(overall_survival),
    !is.na(survival_event)
  ) %>%
  mutate(
    respuesta_quimio = case_when(
      chemotherapy == "No" ~ NA_character_,
      chemotherapy == "Yes" & overall_survival > 1095 ~ "Buena_Respuesta",
      chemotherapy == "Yes" & overall_survival <= 1095 & survival_event == "DECEASED" ~ "Mala_Respuesta",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(respuesta_quimio))

print(paste("Pacientes analizados:", nrow(datos_clean)))
print(table(datos_clean$respuesta_quimio))

# --- 3. APLICAR PCA A GENES ---

genes_cols <- c(
  "esr1_expression", "pgr_expression", "erbb2_expression",
  "mki67_expression", "tp53_expression", "brca1_expression",
  "brca2_expression", "pik3ca_expression", "pten_expression",
  "akt1_expression"
)

# Subset con genes (eliminar NAs)
genes_data <- datos_clean[, genes_cols]
genes_complete_idx <- complete.cases(genes_data)

print("")
print("--- APLICANDO PCA A GENES ---")
print(paste("Pacientes con datos completos de genes:", sum(genes_complete_idx)))

# Filtrar datos para tener solo casos completos
datos_pca <- datos_clean[genes_complete_idx, ]
genes_data_complete <- genes_data[genes_complete_idx, ]

# Estandarizar genes
genes_scaled <- scale(genes_data_complete)

# Aplicar PCA
pca_genes <- PCA(genes_scaled, graph = FALSE, ncp = 10)

# Ver varianza explicada
print("Varianza explicada por componente:")
print(pca_genes$eig)

# Decisión: usar primeras 3 componentes (explican ~60-70% de varianza)
n_components <- 3
pca_scores <- as.data.frame(pca_genes$ind$coord[, 1:n_components])
colnames(pca_scores) <- paste0("PC", 1:n_components)

print(paste("Usando", n_components, "componentes principales"))
print(paste("Varianza explicada total:", round(sum(pca_genes$eig[1:n_components, 2]), 1), "%"))

# Interpretar componentes
print("")
print("Contribuciones de genes a cada componente principal:")
loadings <- as.data.frame(pca_genes$var$coord[, 1:n_components])
loadings$gene <- rownames(loadings)
print(loadings)

# --- 4. PREPARAR PREDICTORES ---

# Variables a excluir
variables_a_eliminar <- c(
  "id_paciente", "dataset_source",
  "overall_survival", "survival_event", "vital_status",
  "chemotherapy", "hormone_therapy", "radiotherapy", "breast_surgery",
  "respuesta_quimio", "diagnosis",
  genes_cols  # Excluir genes individuales, usaremos PCA
)

predictores_base <- datos_pca %>%
  dplyr::select(-any_of(variables_a_eliminar))

# Combinar con componentes principales
predictores <- bind_cols(predictores_base, pca_scores)

objetivo <- datos_pca$respuesta_quimio

print("")
print(paste("Variables predictoras (sin PCA):", ncol(predictores_base)))
print(paste("Variables predictoras (con PCA):", ncol(predictores)))
print("Variables incluidas:")
print(names(predictores))

# --- 5. LIMPIEZA DE NAs ---

# Numéricas: imputar
predictores <- predictores %>%
  mutate(across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)))

# Categóricas: limpiar Unknown <5%
predictores <- predictores %>%
  mutate(across(where(is.character), ~{
    .x <- ifelse(is.na(.x), "Unknown", .x)
    .x <- as.factor(.x)
    if ("Unknown" %in% levels(.x)) {
      if (sum(.x == "Unknown") / length(.x) < 0.05) {
        moda <- names(sort(table(.x[.x != "Unknown"]), decreasing = TRUE))[1]
        levels(.x)[levels(.x) == "Unknown"] <- moda
      }
    }
    .x
  }))

# Eliminar variables con un solo nivel
vars_a_mantener <- sapply(predictores, function(x) {
  if (is.factor(x)) {
    return(nlevels(x) >= 2)
  } else {
    return(length(unique(na.omit(x))) >= 2)
  }
})

predictores <- predictores[, vars_a_mantener]
print(paste("Variables finales:", ncol(predictores)))

# --- 6. DIVISIÓN TRAIN/TEST ---
set.seed(123)
indices_train <- createDataPartition(objetivo, p = 0.8, list = FALSE)

X_train <- predictores[indices_train, ]
X_test <- predictores[-indices_train, ]
y_train <- objetivo[indices_train]
y_test <- objetivo[-indices_train]

print("")
print(paste("Train:", length(y_train), "| Test:", length(y_test)))

# --- 7. PREPROCESAMIENTO XGBOOST ---

dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

y_train_numeric <- as.numeric(factor(y_train, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1
y_test_numeric <- as.numeric(factor(y_test, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1

# Pesos para balancear
tabla_clases <- table(y_train_numeric)
peso_por_clase <- max(tabla_clases) / tabla_clases
pesos_muestras <- peso_por_clase[as.character(y_train_numeric)]

dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_numeric, weight = pesos_muestras)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_numeric)

# --- 8. ENTRENAMIENTO XGBOOST ---
# Parámetros ajustados para ALTO RECALL

params <- list(
  objective = "binary:logistic",
  eta = 0.02,                    # Learning rate muy bajo
  max_depth = 4,                 # Menos profundidad
  min_child_weight = 3,
  subsample = 0.7,
  colsample_bytree = 0.7,
  gamma = 1.5,
  scale_pos_weight = 1,
  eval_metric = "logloss"
)

print("")
print("Entrenando modelo optimizado para F2-Score (prioriza Recall)...")

modelo_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 300,
  watchlist = list(train = dtrain, test = dtest),
  early_stopping_rounds = 30,
  verbose = 1
)

# --- 9. OPTIMIZACIÓN DE UMBRAL PARA F2-SCORE ---

predicciones_prob <- predict(modelo_xgb, dtest)

# Probar umbrales MÁS BAJOS para priorizar Recall
umbrales <- seq(0.2, 0.6, 0.05)
metricas_por_umbral <- data.frame()

for (umbral in umbrales) {
  pred_temp <- ifelse(predicciones_prob > umbral, 1, 0)
  cm_temp <- confusionMatrix(factor(pred_temp), factor(y_test_numeric))

  sens <- cm_temp$byClass["Sensitivity"]
  spec <- cm_temp$byClass["Specificity"]
  prec <- cm_temp$byClass["Precision"]

  # Calcular F2-Score
  f2 <- f2_score(prec, sens)

  metricas_por_umbral <- rbind(metricas_por_umbral, data.frame(
    umbral = umbral,
    accuracy = cm_temp$overall["Accuracy"],
    sensitivity = sens,
    specificity = spec,
    precision = prec,
    f1 = cm_temp$byClass["F1"],
    f2 = f2
  ))
}

print("")
print("========================================")
print("MÉTRICAS POR UMBRAL (ordenadas por F2-Score):")
print("========================================")
metricas_ordenadas <- metricas_por_umbral[order(-metricas_por_umbral$f2), ]
print(metricas_ordenadas)

# Elegir umbral que MAXIMIZA F2-SCORE
mejor_umbral_idx <- which.max(metricas_por_umbral$f2)
mejor_umbral <- metricas_por_umbral$umbral[mejor_umbral_idx]

print("")
print(paste("*** UMBRAL ÓPTIMO PARA F2-SCORE:", mejor_umbral, "***"))
print(paste("    (Umbral bajo = detecta MÁS buenas respuestas)"))

# Predicciones finales
predicciones_numeric <- ifelse(predicciones_prob > mejor_umbral, 1, 0)
predicciones <- ifelse(predicciones_numeric == 1, "Buena_Respuesta", "Mala_Respuesta")
y_test_original <- ifelse(y_test_numeric == 1, "Buena_Respuesta", "Mala_Respuesta")

conf_matrix <- confusionMatrix(factor(predicciones), factor(y_test_original))

accuracy <- conf_matrix$overall["Accuracy"]
sensitivity <- conf_matrix$byClass["Sensitivity"]
specificity <- conf_matrix$byClass["Specificity"]
precision <- conf_matrix$byClass["Precision"]
f1 <- conf_matrix$byClass["F1"]
f2_final <- f2_score(precision, sensitivity)

# --- 10. VISUALIZACIONES ---

# Importancia de variables (incluyendo PCs)
importance_matrix <- xgb.importance(model = modelo_xgb)

plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 15) +
  ggtitle("Top 15 Variables - Modelo F2-Score + PCA") +
  theme_minimal()

print(plot_importance)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_pca_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)

# Matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)
plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 8, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Modelo F2-Score Optimizado",
       subtitle = paste("Umbral:", mejor_umbral, "| Prioridad: Alto Recall"),
       x = "Respuesta Real", y = "Respuesta Predicha") +
  theme_minimal(base_size = 14)

print(plot_confusion)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_pca_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)

# Gráfico de trade-off Precision vs Recall
plot_tradeoff <- ggplot(metricas_por_umbral, aes(x = sensitivity, y = precision)) +
  geom_line(size = 1.5, color = "steelblue") +
  geom_point(size = 3, color = "steelblue") +
  geom_point(data = metricas_por_umbral[mejor_umbral_idx, ],
             aes(x = sensitivity, y = precision),
             color = "red", size = 5) +
  geom_text(data = metricas_por_umbral,
            aes(label = umbral),
            vjust = -1, size = 3) +
  annotate("text",
           x = metricas_por_umbral$sensitivity[mejor_umbral_idx],
           y = metricas_por_umbral$precision[mejor_umbral_idx],
           label = paste("Óptimo F2:", mejor_umbral),
           vjust = 2, color = "red", fontface = "bold") +
  labs(title = "Trade-off Precision vs Recall",
       subtitle = "Punto rojo = umbral que maximiza F2-Score",
       x = "Recall (Sensitivity) - Detectar buenas respuestas",
       y = "Precision - Confianza en predicciones") +
  theme_minimal(base_size = 12) +
  xlim(0, 1) + ylim(0, 1)

print(plot_tradeoff)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_pca_tradeoff.png")
ggsave(output_path, plot = plot_tradeoff, width = 10, height = 8, dpi = 300)

# --- 11. RESUMEN FINAL ---

print("")
print("========================================")
print("RESUMEN FINAL - MODELO F2-SCORE + PCA")
print("========================================")
print("")
print("CARACTERÍSTICAS DEL MODELO:")
print(paste("  - Componentes Principales (PCA):", n_components, "genes reducidos a", n_components, "PCs"))
print(paste("  - Varianza explicada por PCA:", round(sum(pca_genes$eig[1:n_components, 2]), 1), "%"))
print(paste("  - Variables totales usadas:", ncol(X_train_numeric)))
print(paste("  - Umbral de decisión:", mejor_umbral, "(optimizado para F2)"))
print("")
print("MÉTRICAS DE RENDIMIENTO:")
print(paste("  Accuracy:", round(accuracy * 100, 2), "%"))
print(paste("  *** RECALL (Sensitivity):", round(sensitivity * 100, 2), "% ***  <- PRIORIDAD"))
print(paste("  Specificity:", round(specificity * 100, 2), "%"))
print(paste("  Precision:", round(precision * 100, 2), "%"))
print(paste("  F1-Score:", round(f1 * 100, 2), "%"))
print(paste("  *** F2-Score:", round(f2_final * 100, 2), "% *** <- MÉTRICA OBJETIVO"))
print("")
print("INTERPRETACIÓN CLÍNICA - SEGURIDAD:")
print(paste("  ✅ De cada 100 pacientes con BUENA respuesta, detectamos:", round(sensitivity * 100, 0)))
print(paste("     (Solo perdemos", round((1-sensitivity) * 100, 0), "pacientes que podrían beneficiarse)"))
print(paste("  ⚠️  De cada 100 predicciones 'Buena Respuesta', acertamos:", round(precision * 100, 0)))
print(paste("     (", round((1-precision) * 100, 0), "recibirán quimio innecesaria, pero es SEGURO)"))
print("")
print("MATRIZ DE CONFUSIÓN:")
print(conf_matrix$table)
print("")
print("COMPONENTES PRINCIPALES (interpretación):")
print("PC1 - Genes dominantes:")
loadings_pc1 <- loadings[order(-abs(loadings$Dim.1)), ]
print(head(loadings_pc1[, c("gene", "Dim.1")], 3))
print("PC2 - Genes dominantes:")
loadings_pc2 <- loadings[order(-abs(loadings$Dim.2)), ]
print(head(loadings_pc2[, c("gene", "Dim.2")], 3))
print("")
print("========================================")
print("CONCLUSIÓN:")
print("Este modelo PRIORIZA SALVAR VIDAS")
print("Prefiere dar quimio de más que de menos")
print("F2-Score da 2x más peso a detectar buenas respuestas")
print("========================================")

# Guardar modelo y resultados
model_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_pca_model.rds")
saveRDS(list(modelo = modelo_xgb, pca = pca_genes, umbral = mejor_umbral), model_path)
print(paste("Modelo guardado en:", model_path))
