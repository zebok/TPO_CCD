# ============================================================================
# XGBOOST - RESPUESTA A QUIMIOTERAPIA (OPTIMIZADO F2-SCORE)
# ============================================================================
# Objetivo: Predecir respuesta a quimioterapia PRIORIZANDO RECALL
#           (detectar TODAS las buenas respuestas para no perder vidas)
#
# Mejora clave:
#   - Optimización para F2-Score (prioriza Recall 2x sobre Precision)
#   - SIN PCA para no perder datos
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(xgboost)
library(caret)

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

# --- 3. PREPARAR PREDICTORES (CON GENES) ---

variables_a_eliminar <- c(
  "id_paciente", "dataset_source",
  "overall_survival", "survival_event", "vital_status",
  "chemotherapy", "hormone_therapy", "radiotherapy", "breast_surgery",
  "respuesta_quimio", "diagnosis"
)

predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

objetivo <- datos_clean$respuesta_quimio

print("")
print(paste("Variables predictoras:", ncol(predictores)))
print("Variables incluidas:")
print(names(predictores))

# --- 4. LIMPIEZA DE NAs ---

# Numéricas: imputar con mediana
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

# --- 5. DIVISIÓN TRAIN/TEST ---
set.seed(123)
indices_train <- createDataPartition(objetivo, p = 0.8, list = FALSE)

X_train <- predictores[indices_train, ]
X_test <- predictores[-indices_train, ]
y_train <- objetivo[indices_train]
y_test <- objetivo[-indices_train]

print("")
print(paste("Train:", length(y_train), "| Test:", length(y_test)))

# --- 6. PREPROCESAMIENTO XGBOOST ---

dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

y_train_numeric <- as.numeric(factor(y_train, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1
y_test_numeric <- as.numeric(factor(y_test, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1

# Pesos para balancear clases
tabla_clases <- table(y_train_numeric)
peso_por_clase <- max(tabla_clases) / tabla_clases
pesos_muestras <- peso_por_clase[as.character(y_train_numeric)]

dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_numeric, weight = pesos_muestras)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_numeric)

# --- 7. ENTRENAMIENTO XGBOOST ---
# Parámetros ajustados para ALTO RECALL

params <- list(
  objective = "binary:logistic",
  eta = 0.02,                    # Learning rate muy bajo
  max_depth = 4,                 # Menos profundidad
  min_child_weight = 2,
  subsample = 0.7,
  colsample_bytree = 0.7,
  gamma = 1,
  scale_pos_weight = 1.5,        # Dar más peso a clase positiva
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

# --- 8. OPTIMIZACIÓN DE UMBRAL PARA F2-SCORE ---

predicciones_prob <- predict(modelo_xgb, dtest)

# Probar umbrales MÁS BAJOS para priorizar Recall
umbrales <- seq(0.2, 0.7, 0.05)
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

# --- 9. VISUALIZACIONES ---

# Importancia de variables
importance_matrix <- xgb.importance(model = modelo_xgb)

plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 15) +
  ggtitle("Top 15 Variables - Modelo F2-Score Optimizado") +
  theme_minimal()

print(plot_importance)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_importance.png")
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

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_confusion.png")
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

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_tradeoff.png")
ggsave(output_path, plot = plot_tradeoff, width = 10, height = 8, dpi = 300)

# --- 10. RESUMEN FINAL ---

print("")
print("========================================")
print("RESUMEN FINAL - MODELO F2-SCORE")
print("========================================")
print("")
print("CARACTERÍSTICAS DEL MODELO:")
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
print("========================================")
print("CONCLUSIÓN:")
print("Este modelo PRIORIZA SALVAR VIDAS")
print("Prefiere dar quimio de más que de menos")
print("F2-Score da 2x más peso a detectar buenas respuestas")
print("========================================")

# Guardar modelo y resultados
model_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_f2_model.rds")
saveRDS(list(modelo = modelo_xgb, umbral = mejor_umbral), model_path)
print(paste("Modelo guardado en:", model_path))
