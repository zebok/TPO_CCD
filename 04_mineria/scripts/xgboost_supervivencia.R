# ============================================================================
# XGBOOST - PREDICCIÓN DE SUPERVIVENCIA EN CÁNCER DE MAMA
# ============================================================================
# Objetivo: Predecir el tiempo de supervivencia (overall_survival) usando
#           características del tumor, tratamientos y datos demográficos
#           SIN usar expresión génica (muy costosa)
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(xgboost)
library(caret)
library(survival)   # Para análisis de supervivencia

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print(paste("Dataset original:", nrow(datos), "pacientes,", ncol(datos), "variables"))

# --- 2. ANÁLISIS EXPLORATORIO DE SUPERVIVENCIA ---
print("Estadísticas de supervivencia:")
print(summary(datos$overall_survival))

print("Eventos de supervivencia:")
print(table(datos$survival_event, useNA = "always"))

# Convertir survival_event a numérico (DECEASED = 1, LIVING = 0)
datos <- datos %>%
  mutate(survival_event_numeric = case_when(
    survival_event == "DECEASED" ~ 1,
    survival_event == "LIVING" ~ 0,
    TRUE ~ NA_real_
  ))

print("Distribución de eventos (numérico):")
print(table(datos$survival_event_numeric, useNA = "always"))

# --- 3. LIMPIEZA DE DATOS ---

# 3.1. Filtrar pacientes con información de supervivencia
datos_clean <- datos %>%
  filter(!is.na(overall_survival), !is.na(survival_event_numeric))

print(paste("Pacientes con datos de supervivencia:", nrow(datos_clean)))

# 3.2. Seleccionar variables predictoras
# INCLUIMOS (información clínica disponible):
# - Demográficos: edad, raza, menopausal_state
# - Características del tumor: er_status, her2_status, pr_status, tumor_subtype,
#   tumor_grade, tumor_size, lymph_node_status, tumor_stage
# - Tratamientos: chemotherapy, hormone_therapy, radiotherapy, breast_surgery
# - Imagen: 30 características
#
# EXCLUIMOS:
# - Genes (muy costosos según requisito)
# - Variables objetivo (overall_survival, survival_event)

genes_excluir <- c(
  "esr1_expression", "pgr_expression", "erbb2_expression",
  "mki67_expression", "tp53_expression", "brca1_expression",
  "brca2_expression", "pik3ca_expression", "pten_expression",
  "akt1_expression"
)

variables_a_eliminar <- c(
  # Identificadores
  "id_paciente",
  "dataset_source",

  # Variables objetivo
  "overall_survival",
  "survival_event",
  "survival_event_numeric",
  "vital_status",  # Redundante con survival_event

  # Genes (costosos)
  genes_excluir,

  # Diagnosis (redundante)
  "diagnosis"
)

# Seleccionar predictores
predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

# Variables objetivo
tiempo_supervivencia <- datos_clean$overall_survival
evento <- datos_clean$survival_event_numeric

print(paste("Variables predictoras:", ncol(predictores)))
print(paste("Pacientes:", nrow(predictores)))
print(paste("Eventos (muertes):", sum(evento), "de", length(evento),
            paste0("(", round(sum(evento)/length(evento)*100, 1), "%)")))

# 3.3. Manejo de NAs en predictores
# Numéricas: imputar con mediana
predictores <- predictores %>%
  mutate(across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)))

# Categóricas: convertir a factor
predictores <- predictores %>%
  mutate(across(where(is.character), ~as.factor(.)))

# Eliminar variables con un solo nivel
vars_a_mantener <- sapply(predictores, function(x) {
  if (is.factor(x)) {
    return(nlevels(x) >= 2)
  } else {
    return(length(unique(na.omit(x))) >= 2)
  }
})

print(paste("Variables antes de filtrar:", ncol(predictores)))
if (sum(!vars_a_mantener) > 0) {
  print("Variables eliminadas por tener un solo nivel:")
  print(names(predictores)[!vars_a_mantener])
}

predictores <- predictores[, vars_a_mantener]

print(paste("Variables finales:", ncol(predictores)))

# --- 4. DIVISIÓN TRAIN/TEST (80-20) ---
set.seed(123)

# División estratificada por evento (mantener proporción de muertes)
indices_train <- createDataPartition(evento, p = 0.8, list = FALSE)

X_train <- predictores[indices_train, ]
X_test <- predictores[-indices_train, ]
y_train_tiempo <- tiempo_supervivencia[indices_train]
y_test_tiempo <- tiempo_supervivencia[-indices_train]
y_train_evento <- evento[indices_train]
y_test_evento <- evento[-indices_train]

print(paste("Train:", nrow(X_train), "| Test:", nrow(X_test)))
print(paste("Eventos en Train:", sum(y_train_evento), "/", length(y_train_evento)))
print(paste("Eventos en Test:", sum(y_test_evento), "/", length(y_test_evento)))

# --- 5. PREPROCESAMIENTO PARA XGBOOST ---

# Convertir categóricas a dummies
dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

print(paste("Features después de one-hot encoding:", ncol(X_train_numeric)))

# Crear matrices DMatrix
# Para supervivencia, usamos el TIEMPO como label
dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_tiempo)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_tiempo)

# --- 6. ENTRENAMIENTO XGBOOST ---
# Usamos regresión para predecir tiempo de supervivencia

params <- list(
  objective = "reg:squarederror",    # Regresión (predecir tiempo)
  eta = 0.05,                        # Learning rate
  max_depth = 6,                     # Profundidad del árbol
  min_child_weight = 3,
  subsample = 0.8,
  colsample_bytree = 0.8,
  gamma = 1,
  eval_metric = "rmse"               # Error cuadrático medio
)

print("Entrenando modelo XGBoost para supervivencia...")
print("(Predicción de tiempo de supervivencia en días)")

modelo_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 200,
  watchlist = list(train = dtrain, test = dtest),
  early_stopping_rounds = 20,
  verbose = 1
)

print("Entrenamiento completado!")

# --- 7. EVALUACIÓN ---

# Predicciones de tiempo de supervivencia
predicciones_tiempo <- predict(modelo_xgb, dtest)

# Métricas de regresión
mae <- mean(abs(predicciones_tiempo - y_test_tiempo))
rmse <- sqrt(mean((predicciones_tiempo - y_test_tiempo)^2))
r2 <- cor(predicciones_tiempo, y_test_tiempo)^2

print("========================================")
print("MÉTRICAS DE PREDICCIÓN:")
print(paste("MAE (Error Absoluto Medio):", round(mae, 2), "días"))
print(paste("RMSE (Error Cuadrático Medio):", round(rmse, 2), "días"))
print(paste("R² (Coeficiente de determinación):", round(r2, 4)))
print("========================================")

# Análisis por grupos de riesgo
# Clasificar pacientes en grupos según predicción
datos_test_results <- data.frame(
  tiempo_real = y_test_tiempo,
  tiempo_predicho = predicciones_tiempo,
  evento = y_test_evento,
  grupo_riesgo = cut(predicciones_tiempo,
                     breaks = quantile(predicciones_tiempo, probs = c(0, 0.33, 0.67, 1)),
                     labels = c("Alto Riesgo", "Riesgo Medio", "Bajo Riesgo"),
                     include.lowest = TRUE)
)

print("Supervivencia media por grupo de riesgo:")
print(datos_test_results %>%
  group_by(grupo_riesgo) %>%
  summarise(
    n_pacientes = n(),
    tiempo_real_medio = round(mean(tiempo_real), 1),
    tiempo_predicho_medio = round(mean(tiempo_predicho), 1),
    tasa_eventos = round(sum(evento) / n() * 100, 1)
  ))

# --- 8. VISUALIZACIONES ---

# 8.1. Importancia de variables
importance_matrix <- xgb.importance(model = modelo_xgb)
print("Top 20 variables más importantes:")
print(head(importance_matrix, 20))

plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 20) +
  ggtitle("Top 20 Variables - Predicción de Supervivencia") +
  theme_minimal()

print(plot_importance)

output_path <- file.path(project_root, "output", "xgboost_supervivencia_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# 8.2. Gráfico: Tiempo real vs Predicho
plot_scatter <- ggplot(datos_test_results, aes(x = tiempo_real, y = tiempo_predicho)) +
  geom_point(aes(color = factor(evento)), alpha = 0.6, size = 3) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "red", size = 1) +
  scale_color_manual(values = c("0" = "steelblue", "1" = "darkred"),
                     labels = c("Vivo", "Fallecido"),
                     name = "Estado") +
  labs(title = "Supervivencia Real vs Predicha",
       subtitle = paste("R² =", round(r2, 3), "| RMSE =", round(rmse, 1), "días"),
       x = "Tiempo Real de Supervivencia (días)",
       y = "Tiempo Predicho (días)") +
  theme_minimal(base_size = 12)

print(plot_scatter)

output_path <- file.path(project_root, "output", "xgboost_supervivencia_scatter.png")
ggsave(output_path, plot = plot_scatter, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# 8.3. Distribución de predicciones por grupo de riesgo
plot_boxplot <- ggplot(datos_test_results, aes(x = grupo_riesgo, y = tiempo_real, fill = grupo_riesgo)) +
  geom_boxplot(alpha = 0.7) +
  geom_jitter(width = 0.2, alpha = 0.3) +
  scale_fill_manual(values = c("Alto Riesgo" = "#d73027",
                                "Riesgo Medio" = "#fee08b",
                                "Bajo Riesgo" = "#1a9850")) +
  labs(title = "Distribución de Supervivencia Real por Grupo de Riesgo Predicho",
       x = "Grupo de Riesgo",
       y = "Tiempo de Supervivencia Real (días)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none")

print(plot_boxplot)

output_path <- file.path(project_root, "output", "xgboost_supervivencia_grupos.png")
ggsave(output_path, plot = plot_boxplot, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# --- 9. GUARDAR MODELO ---
model_path <- file.path(project_root, "output", "xgboost_supervivencia_model.rds")
saveRDS(modelo_xgb, model_path)
print(paste("Modelo guardado en:", model_path))

# Guardar tabla de resultados
results_path <- file.path(project_root, "output", "supervivencia_resultados_test.csv")
write_csv(datos_test_results, results_path)
print(paste("Resultados guardados en:", results_path))

# --- 10. RESUMEN FINAL ---
print("========================================")
print("RESUMEN FINAL - ANÁLISIS DE SUPERVIVENCIA")
print("========================================")
print(paste("Pacientes analizados:", nrow(datos_clean)))
print(paste("Variables usadas:", ncol(X_train_numeric)))
print("")
print("MÉTRICAS DE RENDIMIENTO:")
print(paste("  MAE:", round(mae, 2), "días (~", round(mae/30.44, 1), "meses)"))
print(paste("  RMSE:", round(rmse, 2), "días (~", round(rmse/30.44, 1), "meses)"))
print(paste("  R²:", round(r2, 4)))
print("")
print("GRUPOS DE RIESGO:")
print(datos_test_results %>%
  group_by(grupo_riesgo) %>%
  summarise(
    n = n(),
    supervivencia_media_dias = round(mean(tiempo_real), 1),
    supervivencia_media_meses = round(mean(tiempo_real)/30.44, 1),
    tasa_mortalidad = paste0(round(sum(evento)/n()*100, 1), "%")
  ))
print("")
print("Variables más importantes (top 5):")
print(head(importance_matrix[, c("Feature", "Gain")], 5))
print("")
print("Este modelo predice tiempo de supervivencia usando:")
print("  ✅ Características del tumor (stage, grade, size, receptores)")
print("  ✅ Tratamientos (quimio, hormonal, radio, cirugía)")
print("  ✅ Demográficos (edad, raza, menopausia)")
print("  ✅ Características de imagen (30 features)")
print("  ❌ NO usa expresión génica (muy costosa)")
print("========================================")
