# ============================================================================
# XGBOOST - PREDICCIÓN DE MEJOR TERAPIA (MULTICLASE)
# ============================================================================
# Objetivo: Predecir qué combinación de tratamientos es más efectiva
#           para cada paciente según sus características
#
# Clases a predecir:
#   1. Solo_Quimio
#   2. Solo_Hormonal
#   3. Quimio_Hormonal (ambas)
#   4. Sin_Tratamiento_Sistemico
#
# Definición de "mejor terapia": La que recibió y sobrevivió >3 años
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(xgboost)
library(caret)

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print("============================================")
print("PREDICCIÓN DE MEJOR TERAPIA (MULTICLASE)")
print("============================================")
print("")

# --- 2. DEFINIR VARIABLE OBJETIVO: MEJOR TERAPIA ---

# Crear variable de combinación de tratamientos
datos_clean <- datos %>%
  filter(
    !is.na(chemotherapy),
    !is.na(hormone_therapy),
    !is.na(overall_survival),
    !is.na(survival_event)
  ) %>%
  mutate(
    # Crear combinación de tratamientos
    terapia_recibida = case_when(
      chemotherapy == "Yes" & hormone_therapy == "Yes" ~ "Quimio_Hormonal",
      chemotherapy == "Yes" & hormone_therapy == "No" ~ "Solo_Quimio",
      chemotherapy == "No" & hormone_therapy == "Yes" ~ "Solo_Hormonal",
      chemotherapy == "No" & hormone_therapy == "No" ~ "Sin_Tratamiento_Sistemico",
      TRUE ~ NA_character_
    ),

    # Definir si tuvo buena respuesta (>3 años de supervivencia)
    buena_respuesta = overall_survival > 1095,

    # Definir "mejor terapia" como: terapia recibida + buena respuesta
    mejor_terapia = case_when(
      # Solo incluir pacientes con buena respuesta para definir "mejor terapia"
      buena_respuesta ~ terapia_recibida,
      # Excluir pacientes que murieron <3 años (resultado malo)
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(mejor_terapia))

print(paste("Pacientes con buena respuesta (>3 años):", nrow(datos_clean)))
print("")
print("Distribución de mejor terapia:")
print(table(datos_clean$mejor_terapia))
print("")
print("Proporción por clase:")
print(round(prop.table(table(datos_clean$mejor_terapia)) * 100, 1))

# --- 3. PREPARAR PREDICTORES ---
# Usaremos: genes, características tumorales, demográficos
# NO usaremos: tratamientos (son lo que queremos predecir), outcomes

variables_a_eliminar <- c(
  # Identificadores
  "id_paciente",
  "dataset_source",

  # Outcomes
  "overall_survival",
  "survival_event",
  "vital_status",

  # Tratamientos (son el objetivo)
  "chemotherapy",
  "hormone_therapy",
  "radiotherapy",
  "breast_surgery",

  # Variables creadas
  "terapia_recibida",
  "buena_respuesta",
  "mejor_terapia",

  # Diagnosis redundante
  "diagnosis"
)

predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

objetivo <- datos_clean$mejor_terapia

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
print("")
print("Distribución en TRAIN:")
print(table(y_train))
print("")
print("Distribución en TEST:")
print(table(y_test))

# --- 6. PREPROCESAMIENTO XGBOOST ---

dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

# Para multiclase, necesitamos codificar las etiquetas como números (0, 1, 2, 3)
clases_unicas <- sort(unique(c(y_train, y_test)))
y_train_numeric <- as.numeric(factor(y_train, levels = clases_unicas)) - 1
y_test_numeric <- as.numeric(factor(y_test, levels = clases_unicas)) - 1

print("Mapeo de clases:")
for (i in seq_along(clases_unicas)) {
  print(paste("  ", i-1, "->", clases_unicas[i]))
}

# Pesos para balancear clases (multiclase)
tabla_clases <- table(y_train_numeric)
peso_por_clase <- max(tabla_clases) / tabla_clases
pesos_muestras <- peso_por_clase[as.character(y_train_numeric)]

dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_numeric, weight = pesos_muestras)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_numeric)

# --- 7. ENTRENAMIENTO XGBOOST (MULTICLASE) ---

num_clases <- length(clases_unicas)

params <- list(
  objective = "multi:softprob",  # Clasificación multiclase
  num_class = num_clases,
  eta = 0.03,
  max_depth = 5,
  min_child_weight = 2,
  subsample = 0.8,
  colsample_bytree = 0.8,
  gamma = 1.5,
  eval_metric = "mlogloss"
)

print("")
print(paste("Entrenando modelo multiclase con", num_clases, "clases..."))

modelo_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 200,
  watchlist = list(train = dtrain, test = dtest),
  early_stopping_rounds = 20,
  verbose = 1
)

# --- 8. PREDICCIONES Y EVALUACIÓN ---

# Predicciones (matriz de probabilidades)
predicciones_prob <- predict(modelo_xgb, dtest)
predicciones_matrix <- matrix(predicciones_prob, ncol = num_clases, byrow = TRUE)

# Clase predicha (la de mayor probabilidad)
predicciones_numeric <- apply(predicciones_matrix, 1, which.max) - 1
predicciones <- clases_unicas[predicciones_numeric + 1]
y_test_original <- clases_unicas[y_test_numeric + 1]

# Matriz de confusión
conf_matrix <- confusionMatrix(factor(predicciones, levels = clases_unicas),
                               factor(y_test_original, levels = clases_unicas))

accuracy <- conf_matrix$overall["Accuracy"]

# --- 9. VISUALIZACIONES ---

# Importancia de variables
importance_matrix <- xgb.importance(model = modelo_xgb)

plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 15) +
  ggtitle("Top 15 Variables - Predicción Mejor Terapia") +
  theme_minimal()

print(plot_importance)

output_path <- file.path(project_root, "output", "xgboost_mejor_terapia_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)

# Matriz de confusión (heatmap)
conf_matrix_df <- as.data.frame(conf_matrix$table)

plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 6, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Mejor Terapia",
       subtitle = paste("Accuracy:", round(accuracy * 100, 1), "%"),
       x = "Terapia Real (Exitosa)", y = "Terapia Predicha") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(plot_confusion)

output_path <- file.path(project_root, "output", "xgboost_mejor_terapia_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)

# Distribución de probabilidades por clase
prob_df <- data.frame(
  clase_real = y_test_original,
  clase_predicha = predicciones,
  predicciones_matrix
)
colnames(prob_df)[3:(2+num_clases)] <- clases_unicas

# Convertir a formato largo para ggplot
prob_long <- prob_df %>%
  pivot_longer(cols = all_of(clases_unicas),
               names_to = "clase_prob",
               values_to = "probabilidad")

plot_prob <- ggplot(prob_long, aes(x = clase_prob, y = probabilidad, fill = clase_real)) +
  geom_boxplot(alpha = 0.7) +
  facet_wrap(~clase_real, nrow = 2) +
  labs(title = "Distribución de Probabilidades Predichas por Clase Real",
       subtitle = "Cada panel = clase real, boxplot = prob asignada a cada terapia",
       x = "Terapia", y = "Probabilidad Predicha") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "none")

print(plot_prob)

output_path <- file.path(project_root, "output", "xgboost_mejor_terapia_probabilidades.png")
ggsave(output_path, plot = plot_prob, width = 12, height = 8, dpi = 300)

# --- 10. MÉTRICAS POR CLASE ---

print("")
print("========================================")
print("RESUMEN FINAL - PREDICCIÓN MEJOR TERAPIA")
print("========================================")
print("")
print("MÉTRICAS GENERALES:")
print(paste("  Accuracy global:", round(accuracy * 100, 2), "%"))
print("")
print("MÉTRICAS POR CLASE:")

# Calcular métricas para cada clase
for (i in seq_along(clases_unicas)) {
  clase <- clases_unicas[i]

  # Sensitivity y Specificity por clase
  if (i <= length(conf_matrix$byClass)) {
    if (is.matrix(conf_matrix$byClass)) {
      sens <- conf_matrix$byClass[i, "Sensitivity"]
      spec <- conf_matrix$byClass[i, "Specificity"]
      prec <- conf_matrix$byClass[i, "Pos Pred Value"]
      f1 <- conf_matrix$byClass[i, "F1"]
    } else {
      sens <- conf_matrix$byClass["Sensitivity"]
      spec <- conf_matrix$byClass["Specificity"]
      prec <- conf_matrix$byClass["Pos Pred Value"]
      f1 <- conf_matrix$byClass["F1"]
    }

    print(paste("Clase:", clase))
    print(paste("  Sensitivity (Recall):", round(sens * 100, 1), "%"))
    print(paste("  Specificity:", round(spec * 100, 1), "%"))
    print(paste("  Precision:", round(prec * 100, 1), "%"))
    print(paste("  F1-Score:", round(f1 * 100, 1), "%"))
    print("")
  }
}

print("MATRIZ DE CONFUSIÓN:")
print(conf_matrix$table)
print("")

print("INTERPRETACIÓN CLÍNICA:")
print("  - Modelo predice qué terapia es más efectiva para cada paciente")
print("  - Basado en pacientes que SOBREVIVIERON >3 años con esa terapia")
print("  - Puede ayudar a personalizar decisiones de tratamiento")
print("")

# Top 10 variables importantes con interpretación
print("TOP 10 VARIABLES MÁS IMPORTANTES:")
top_vars <- head(importance_matrix, 10)
for (i in 1:nrow(top_vars)) {
  print(paste(i, ".", top_vars$Feature[i], "-", round(top_vars$Gain[i] * 100, 1), "%"))
}

print("")
print("========================================")

# Guardar modelo y resultados
model_path <- file.path(project_root, "output", "xgboost_mejor_terapia_model.rds")
saveRDS(list(modelo = modelo_xgb, clases = clases_unicas), model_path)
print(paste("Modelo guardado en:", model_path))

# Guardar predicciones
resultados <- data.frame(
  terapia_real = y_test_original,
  terapia_predicha = predicciones,
  predicciones_matrix
)
colnames(resultados)[3:(2+num_clases)] <- paste0("prob_", clases_unicas)

output_csv <- file.path(project_root, "output", "mejor_terapia_resultados_test.csv")
write_csv(resultados, output_csv)
print(paste("Resultados guardados en:", output_csv))
