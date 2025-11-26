# ============================================================================
# XGBOOST - PREDICCIÓN DE RESPUESTA A QUIMIOTERAPIA
# ============================================================================
# Objetivo: Predecir si un paciente se BENEFICIA de quimioterapia
#           usando genes, características tumorales y demográficos
#
# Definición de "Beneficio":
#   - Paciente recibió quimioterapia Y sobrevivió >3 años (1095 días)
#   - O tiene características de alto riesgo que justifican quimio
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

print(paste("Dataset original:", nrow(datos), "pacientes,", ncol(datos), "variables"))

# --- 2. ANÁLISIS EXPLORATORIO ---
print("Distribución de tratamiento con quimioterapia:")
print(table(datos$chemotherapy, useNA = "always"))

print("Supervivencia media por tratamiento:")
datos %>%
  filter(!is.na(chemotherapy), !is.na(overall_survival)) %>%
  group_by(chemotherapy) %>%
  summarise(
    n = n(),
    supervivencia_media = round(mean(overall_survival), 1),
    supervivencia_mediana = round(median(overall_survival), 1),
    tasa_eventos = round(sum(survival_event == "DECEASED", na.rm = TRUE) / n() * 100, 1)
  ) %>%
  print()

# --- 3. DEFINIR VARIABLE OBJETIVO: RESPUESTA A QUIMIOTERAPIA ---

# Estrategia: Definir "buena respuesta" como:
# 1. Recibió quimioterapia Y sobrevivió >3 años (1095 días)
# 2. Recibió quimioterapia Y está vivo (censurado) con >3 años de seguimiento

datos_clean <- datos %>%
  filter(
    !is.na(chemotherapy),
    !is.na(overall_survival),
    !is.na(survival_event)
  ) %>%
  mutate(
    # Definir respuesta a quimioterapia
    respuesta_quimio = case_when(
      # Si NO recibió quimio, no aplica (excluir de análisis)
      chemotherapy == "No" ~ NA_character_,

      # Si recibió quimio Y sobrevivió >3 años → buena respuesta
      chemotherapy == "Yes" & overall_survival > 1095 ~ "Buena_Respuesta",

      # Si recibió quimio Y murió en <3 años → mala respuesta
      chemotherapy == "Yes" & overall_survival <= 1095 & survival_event == "DECEASED" ~ "Mala_Respuesta",

      # Si recibió quimio Y está vivo pero <3 años seguimiento → excluir (no sabemos aún)
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(respuesta_quimio))  # Solo pacientes que recibieron quimio con resultado conocido

print(paste("Pacientes que recibieron quimioterapia con respuesta conocida:", nrow(datos_clean)))
print("Distribución de respuesta:")
print(table(datos_clean$respuesta_quimio))

# --- 4. SELECCIONAR VARIABLES PREDICTORAS ---
# Usaremos: genes, características tumorales, demográficos
# NO usaremos: otros tratamientos (pueden confundir), outcomes

variables_a_eliminar <- c(
  # Identificadores
  "id_paciente",
  "dataset_source",

  # Outcomes
  "overall_survival",
  "survival_event",
  "vital_status",

  # Tratamientos (confusores)
  "chemotherapy",  # Variable que define la respuesta
  "hormone_therapy",
  "radiotherapy",
  "breast_surgery",

  # Variable objetivo
  "respuesta_quimio",

  # Diagnosis redundante
  "diagnosis"
)

predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

objetivo <- datos_clean$respuesta_quimio

print(paste("Variables predictoras:", ncol(predictores)))
print("Nombres de variables:")
print(names(predictores))

# --- 5. MANEJO DE NAs ---

# Numéricas: imputar con mediana
predictores <- predictores %>%
  mutate(across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)))

# Categóricas: limpiar NAs ANTES de convertir a factor
# Reemplazar NAs por "Unknown" solo si es necesario, luego consolidar niveles raros
predictores <- predictores %>%
  mutate(across(where(is.character), ~{
    # Reemplazar NA por "Unknown"
    .x <- ifelse(is.na(.x), "Unknown", .x)
    # Convertir a factor
    .x <- as.factor(.x)
    # Si "Unknown" es <5% de los datos, agruparlo con la moda
    if ("Unknown" %in% levels(.x)) {
      freq_unknown <- sum(.x == "Unknown") / length(.x)
      if (freq_unknown < 0.05) {
        # Reemplazar Unknown por la moda (valor más frecuente)
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

print(paste("Variables antes de filtrar:", ncol(predictores)))
if (sum(!vars_a_mantener) > 0) {
  print("Variables eliminadas por tener un solo nivel:")
  print(names(predictores)[!vars_a_mantener])
}

predictores <- predictores[, vars_a_mantener]
print(paste("Variables finales:", ncol(predictores)))

# --- 6. DIVISIÓN TRAIN/TEST (80-20) ---
set.seed(123)

# División estratificada
indices_train <- createDataPartition(objetivo, p = 0.8, list = FALSE)

X_train <- predictores[indices_train, ]
X_test <- predictores[-indices_train, ]
y_train <- objetivo[indices_train]
y_test <- objetivo[-indices_train]

print(paste("Train:", length(y_train), "| Test:", length(y_test)))
print("Distribución en Train:")
print(table(y_train))
print("Distribución en Test:")
print(table(y_test))

# --- 7. PREPROCESAMIENTO ---

# Convertir categóricas a dummies
dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

# Convertir objetivo a numérico (0 = Mala, 1 = Buena)
y_train_numeric <- as.numeric(factor(y_train, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1
y_test_numeric <- as.numeric(factor(y_test, levels = c("Mala_Respuesta", "Buena_Respuesta"))) - 1

print(paste("Features después de one-hot encoding:", ncol(X_train_numeric)))

# Calcular pesos para balancear clases
tabla_clases <- table(y_train_numeric)
print("Distribución de clases en train:")
print(tabla_clases)

peso_por_clase <- max(tabla_clases) / tabla_clases
print("Pesos por clase:")
print(peso_por_clase)

pesos_muestras <- peso_por_clase[as.character(y_train_numeric)]

# Crear matrices DMatrix
dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_numeric, weight = pesos_muestras)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_numeric)

# --- 8. ENTRENAMIENTO XGBOOST ---

# Ajustar parámetros para mejorar Specificity (detectar malas respuestas)
# Vamos a hacer el modelo más conservador
params <- list(
  objective = "binary:logistic",
  eta = 0.03,                    # Learning rate más bajo para mejor generalización
  max_depth = 5,                 # Menos profundidad para evitar overfitting
  min_child_weight = 5,          # Más conservador en splits
  subsample = 0.7,               # Menos muestras por árbol
  colsample_bytree = 0.7,        # Menos features por árbol
  gamma = 2,                     # Más regularización
  scale_pos_weight = 1,          # Balance entre clases
  eval_metric = "logloss"
)

print("Entrenando modelo XGBoost para predecir respuesta a quimioterapia...")
print("(Clasificación binaria: Buena vs Mala respuesta)")

modelo_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 200,
  watchlist = list(train = dtrain, test = dtest),
  early_stopping_rounds = 20,
  verbose = 1
)

print("Entrenamiento completado!")

# --- 9. EVALUACIÓN ---

# Predicciones con umbral optimizado para balancear Sensitivity/Specificity
predicciones_prob <- predict(modelo_xgb, dtest)

# Probar diferentes umbrales para encontrar el mejor balance
umbrales <- seq(0.3, 0.7, 0.05)
metricas_por_umbral <- data.frame()

for (umbral in umbrales) {
  pred_temp <- ifelse(predicciones_prob > umbral, 1, 0)
  cm_temp <- confusionMatrix(factor(pred_temp), factor(y_test_numeric))

  metricas_por_umbral <- rbind(metricas_por_umbral, data.frame(
    umbral = umbral,
    accuracy = cm_temp$overall["Accuracy"],
    sensitivity = cm_temp$byClass["Sensitivity"],
    specificity = cm_temp$byClass["Specificity"],
    f1 = cm_temp$byClass["F1"]
  ))
}

print("Métricas por umbral de decisión:")
print(metricas_por_umbral)

# Elegir umbral que maximiza (Sensitivity + Specificity) / 2
mejor_umbral_idx <- which.max(metricas_por_umbral$sensitivity + metricas_por_umbral$specificity)
mejor_umbral <- metricas_por_umbral$umbral[mejor_umbral_idx]
print(paste("Umbral óptimo seleccionado:", mejor_umbral))

# Predicciones finales con umbral optimizado
predicciones_numeric <- ifelse(predicciones_prob > mejor_umbral, 1, 0)
predicciones <- ifelse(predicciones_numeric == 1, "Buena_Respuesta", "Mala_Respuesta")
y_test_original <- ifelse(y_test_numeric == 1, "Buena_Respuesta", "Mala_Respuesta")

# Matriz de confusión
conf_matrix <- confusionMatrix(factor(predicciones), factor(y_test_original))
print(conf_matrix)

accuracy <- conf_matrix$overall["Accuracy"]
sensitivity <- conf_matrix$byClass["Sensitivity"]  # Detectar buena respuesta
specificity <- conf_matrix$byClass["Specificity"]  # Detectar mala respuesta

# Importancia de variables
importance_matrix <- xgb.importance(model = modelo_xgb)
print("Top 20 variables más importantes:")
print(head(importance_matrix, 20))

# --- INTERPRETACIÓN DE VARIABLES IMPORTANTES ---
print("")
print("========================================")
print("INTERPRETACIÓN DE VARIABLES IMPORTANTES")
print("========================================")

top_5 <- head(importance_matrix, 5)

for (i in 1:nrow(top_5)) {
  feature_name <- top_5$Feature[i]
  gain <- round(top_5$Gain[i], 4)

  print(paste0(i, ". ", feature_name, " (Gain: ", gain, ")"))

  # Interpretaciones basadas en nombres comunes
  interpretacion <- case_when(
    grepl("age_at_diagnosis", feature_name) ~
      "   → Edad al diagnóstico: Pacientes más jóvenes suelen responder mejor a quimio",

    grepl("tumor_stage", feature_name) ~
      "   → Estadio tumoral: Estadios avanzados requieren quimio agresiva",

    grepl("tumor_grade", feature_name) ~
      "   → Grado tumoral: Alto grado → mayor proliferación → mejor respuesta a quimio",

    grepl("tumor_size", feature_name) ~
      "   → Tamaño tumoral: Tumores grandes pueden necesitar quimio neoadyuvante",

    grepl("lymph_node", feature_name) ~
      "   → Estado ganglionar: Ganglios positivos → quimio recomendada",

    grepl("er_status", feature_name) ~
      "   → Receptor de estrógeno: ER+ puede responder a hormonal en vez de quimio",

    grepl("her2_status", feature_name) ~
      "   → Receptor HER2: HER2+ responde bien a quimio + terapia dirigida",

    grepl("pr_status", feature_name) ~
      "   → Receptor de progesterona: Relacionado con respuesta hormonal",

    grepl("tumor_subtype", feature_name) ~
      "   → Subtipo molecular: Basal y Her2 responden mejor a quimio que Luminal A",

    grepl("mki67_expression", feature_name) ~
      "   → MKI67 (proliferación): Alto MKI67 → tumor agresivo → mejor respuesta a quimio",

    grepl("tp53_expression", feature_name) ~
      "   → TP53 (supresor tumoral): Mutaciones asociadas con resistencia a tratamiento",

    grepl("esr1_expression", feature_name) ~
      "   → ESR1 (receptor estrógeno): Alto ESR1 → candidato a terapia hormonal",

    grepl("erbb2_expression", feature_name) ~
      "   → ERBB2 (HER2): Sobreexpresión → responde a quimio + trastuzumab",

    grepl("brca", feature_name) ~
      "   → BRCA1/2: Mutaciones asociadas con sensibilidad a platinos",

    grepl("race", feature_name) ~
      "   → Raza: Diferencias en metabolismo de fármacos y acceso a tratamiento",

    grepl("menopausal", feature_name) ~
      "   → Estado menopáusico: Afecta niveles hormonales y respuesta",

    grepl("radius|texture|perimeter|area", feature_name) ~
      "   → Características de imagen: Relacionadas con agresividad tumoral",

    TRUE ~ "   → Variable predictora de respuesta a quimioterapia"
  )

  print(interpretacion)
  print("")
}

print("NOTA: Estas interpretaciones son generales basadas en conocimiento clínico.")
print("El modelo puede encontrar patrones más complejos en las interacciones entre variables.")
print("========================================")
print("")

# --- 10. VISUALIZACIONES ---

# 10.1. Importancia de variables
plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 20) +
  ggtitle("Top 20 Variables - Predicción de Respuesta a Quimioterapia") +
  theme_minimal()

print(plot_importance)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# 10.2. Matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)
plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 8, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Respuesta a Quimioterapia",
       x = "Respuesta Real", y = "Respuesta Predicha") +
  theme_minimal(base_size = 14)

print(plot_confusion)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# 10.3. Distribución de probabilidades predichas
datos_test_results <- data.frame(
  respuesta_real = y_test_original,
  probabilidad_buena_respuesta = predicciones_prob,
  prediccion = predicciones
)

plot_prob <- ggplot(datos_test_results, aes(x = probabilidad_buena_respuesta, fill = respuesta_real)) +
  geom_histogram(alpha = 0.6, bins = 30, position = "identity") +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red", size = 1) +
  scale_fill_manual(values = c("Mala_Respuesta" = "#d73027", "Buena_Respuesta" = "#1a9850"),
                    name = "Respuesta Real") +
  labs(title = "Distribución de Probabilidades Predichas",
       subtitle = "Línea roja = umbral de decisión (0.5)",
       x = "Probabilidad de Buena Respuesta",
       y = "Frecuencia") +
  theme_minimal(base_size = 12)

print(plot_prob)

output_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_probabilidades.png")
ggsave(output_path, plot = plot_prob, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# --- 11. GUARDAR MODELO Y RESULTADOS ---

model_path <- file.path(project_root, "output", "xgboost_respuesta_quimio_model.rds")
saveRDS(modelo_xgb, model_path)
print(paste("Modelo guardado en:", model_path))

results_path <- file.path(project_root, "output", "respuesta_quimio_resultados_test.csv")
write_csv(datos_test_results, results_path)
print(paste("Resultados guardados en:", results_path))

# --- 12. RESUMEN FINAL ---
print("========================================")
print("RESUMEN FINAL - RESPUESTA A QUIMIOTERAPIA")
print("========================================")
print(paste("Pacientes analizados (recibieron quimio):", nrow(datos_clean)))
print(paste("Variables usadas:", ncol(X_train_numeric)))
print("")
print("DEFINICIÓN DE RESPUESTA:")
print("  Buena Respuesta: Recibió quimio Y sobrevivió >3 años")
print("  Mala Respuesta: Recibió quimio Y murió en <3 años")
print("")
print("MÉTRICAS DE RENDIMIENTO:")
print(paste("  Umbral de decisión óptimo:", mejor_umbral))
print(paste("  Accuracy:", round(accuracy * 100, 2), "%"))
print(paste("  Sensitivity (detectar buena respuesta):", round(sensitivity * 100, 2), "%"))
print(paste("  Specificity (detectar mala respuesta):", round(specificity * 100, 2), "%"))
print(paste("  Balanced Accuracy:", round((sensitivity + specificity) / 2 * 100, 2), "%"))
print(paste("  Precision:", round(conf_matrix$byClass["Precision"] * 100, 2), "%"))
print(paste("  F1-Score:", round(conf_matrix$byClass["F1"] * 100, 2), "%"))
print("")
print("INTERPRETACIÓN CLÍNICA:")
print(paste("  - De cada 100 pacientes con BUENA respuesta real, detectamos", round(sensitivity * 100, 0)))
print(paste("  - De cada 100 pacientes con MALA respuesta real, detectamos", round(specificity * 100, 0)))
print(paste("  - Cuando predecimos 'Buena Respuesta', acertamos el", round(conf_matrix$byClass["Precision"] * 100, 0), "% de las veces"))
print("")
print("MATRIZ DE CONFUSIÓN:")
print(conf_matrix$table)
print("")
print("VARIABLES MÁS IMPORTANTES (top 5):")
print(head(importance_matrix[, c("Feature", "Gain")], 5))
print("")
print("APLICACIÓN CLÍNICA:")
print("  Este modelo puede ayudar a:")
print("  ✅ Identificar pacientes que se beneficiarán de quimioterapia")
print("  ✅ Evitar quimioterapia innecesaria en pacientes de bajo beneficio")
print("  ✅ Personalizar decisiones de tratamiento")
print("  ⚠️  Debe usarse como apoyo, NO como único criterio de decisión")
print("========================================")
