# ============================================================================
# XGBOOST - PREDICCIÓN DE TUMOR_STAGE
# ============================================================================
# Objetivo: Predecir la etapa del tumor (tumor_stage) usando características
#           de genes, imagen y variables clínicas
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(xgboost)
library(caret)        # Para división train/test y métricas
library(Matrix)       # Para matrices sparse

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print(paste("Dataset original:", nrow(datos), "pacientes,", ncol(datos), "variables"))

# --- 2. ANÁLISIS EXPLORATORIO ---
print("Distribución de tumor_stage:")
print(table(datos$tumor_stage, useNA = "always"))

# Porcentaje de NAs por variable
na_porcentaje <- colMeans(is.na(datos)) * 100
print("Variables con más de 50% de NAs:")
print(na_porcentaje[na_porcentaje > 50])

# --- 3. LIMPIEZA DE DATOS ---

# 3.1. Eliminar pacientes sin tumor_stage (no podemos predecir sin etiqueta)
datos_clean <- datos %>%
  filter(!is.na(tumor_stage))

print(paste("Después de eliminar NAs en tumor_stage:", nrow(datos_clean), "pacientes"))

# 3.2. Seleccionar variables predictoras
# EXCLUIMOS:
# - Identificadores y metadata
# - Variables de outcome (supervivencia)
# - Variables que describen el tumor (son consecuencia del stage)
# - Tratamientos (son decididos DESPUÉS del stage)

variables_a_eliminar <- c(
  # Identificadores
  "id_paciente",
  "dataset_source",

  # Outcomes de supervivencia
  "survival_event",
  "overall_survival",
  "vital_status",

  # Variable objetivo
  "tumor_stage",

  # Características del tumor (no las usamos para predecir stage)
  "er_status",
  "her2_status",
  "pr_status",
  "tumor_subtype",
  "tumor_grade",
  "tumor_size",
  "lymph_node_status",
  "diagnosis",

  # Tratamientos (se deciden después del diagnóstico de stage)
  "breast_surgery",
  "chemotherapy",
  "hormone_therapy",
  "radiotherapy",

  # Demográficos excluidos
  "gender"
)

# Variables predictoras (todas menos las eliminadas)
# USAREMOS: edad, demográficos, genes, características de imagen
predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

# Variable objetivo
objetivo <- datos_clean$tumor_stage

# 3.3. Manejo de NAs en predictores
# Estrategia: Imputar NAs con la mediana para numéricas, eliminar categóricas con un solo nivel

# Numéricas: imputar con mediana
predictores <- predictores %>%
  mutate(across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)))

# Categóricas: convertir a factor
predictores <- predictores %>%
  mutate(across(where(is.character), ~as.factor(.)))

# Eliminar variables categóricas con menos de 2 niveles (no aportan información)
# También eliminar variables con todos NAs o un solo valor
vars_a_mantener <- sapply(predictores, function(x) {
  if (is.factor(x)) {
    return(nlevels(x) >= 2)  # Al menos 2 niveles
  } else {
    return(length(unique(na.omit(x))) >= 2)  # Al menos 2 valores únicos
  }
})

print(paste("Variables antes de filtrar:", ncol(predictores)))
print("Variables eliminadas por tener un solo nivel:")
print(names(predictores)[!vars_a_mantener])

predictores <- predictores[, vars_a_mantener]

print(paste("Predictores listos:", ncol(predictores), "variables"))
print(paste("Clases en tumor_stage:", length(unique(objetivo))))

# --- 4. DIVISIÓN TRAIN/TEST (80-20) ---
set.seed(123)  # Reproducibilidad

# División estratificada (mantener proporción de clases)
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

# --- 5. PREPROCESAMIENTO PARA XGBOOST ---

# XGBoost requiere variables numéricas
# Convertir categóricas a dummies (one-hot encoding)

# Crear objeto dummyVars
dummies <- dummyVars(~ ., data = X_train, fullRank = TRUE)

# Aplicar a train y test
X_train_numeric <- predict(dummies, newdata = X_train)
X_test_numeric <- predict(dummies, newdata = X_test)

# Convertir objetivo a numérico (0, 1, 2, ...)
# XGBoost multiclase requiere etiquetas empezando en 0
y_train_numeric <- as.numeric(factor(y_train)) - 1
y_test_numeric <- as.numeric(factor(y_test)) - 1
clases_nombres <- levels(factor(y_train))

print(paste("Después de one-hot encoding:", ncol(X_train_numeric), "features"))

# Calcular pesos para balancear clases
# Dar más peso a las clases minoritarias
tabla_clases <- table(y_train_numeric)
print("Distribución de clases en train:")
print(tabla_clases)

# Calcular peso inverso a la frecuencia
peso_por_clase <- max(tabla_clases) / tabla_clases
print("Pesos por clase (para balancear):")
print(peso_por_clase)

# Asignar peso a cada muestra según su clase
pesos_muestras <- peso_por_clase[as.character(y_train_numeric)]

# Crear matrices DMatrix para XGBoost
dtrain <- xgb.DMatrix(data = X_train_numeric, label = y_train_numeric, weight = pesos_muestras)
dtest <- xgb.DMatrix(data = X_test_numeric, label = y_test_numeric)

# --- 6. ENTRENAMIENTO XGBOOST ---

# Parámetros del modelo (optimizados para clases desbalanceadas)
params <- list(
  objective = "multi:softmax",           # Clasificación multiclase
  num_class = length(unique(y_train_numeric)),  # Número de clases
  eta = 0.05,                            # Learning rate más bajo para mejor generalización
  max_depth = 8,                         # Más profundidad para capturar patrones complejos
  min_child_weight = 3,                  # Evitar overfitting en clases pequeñas
  subsample = 0.8,                       # % de muestras por árbol
  colsample_bytree = 0.8,                # % de features por árbol
  gamma = 1,                             # Regularización
  eval_metric = "mlogloss"               # Métrica de evaluación
)

# Entrenar con early stopping
print("Entrenando modelo XGBoost con clases balanceadas...")
print("(Esto puede tardar un poco más debido a eta=0.05)")
modelo_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 200,                         # Más iteraciones debido a eta bajo
  watchlist = list(train = dtrain, test = dtest),
  early_stopping_rounds = 20,            # Más paciencia para learning rate bajo
  verbose = 1
)

print("Entrenamiento completado!")

# --- 7. EVALUACIÓN ---

# Predicciones en test
predicciones_numeric <- predict(modelo_xgb, dtest)
predicciones <- clases_nombres[predicciones_numeric + 1]  # Convertir a etiquetas originales
y_test_original <- clases_nombres[y_test_numeric + 1]

# Matriz de confusión
conf_matrix <- confusionMatrix(factor(predicciones), factor(y_test_original))
print(conf_matrix)

# Accuracy
accuracy <- conf_matrix$overall["Accuracy"]
print(paste("Accuracy en Test:", round(accuracy * 100, 2), "%"))

# Importancia de variables (top 20)
importance_matrix <- xgb.importance(model = modelo_xgb)
print("Top 20 variables más importantes:")
print(head(importance_matrix, 20))

# --- 8. VISUALIZACIONES ---

# Gráfico de importancia de variables
plot_importance <- xgb.ggplot.importance(importance_matrix, top_n = 20) +
  ggtitle("Top 20 Variables Más Importantes - Predicción de Tumor Stage") +
  theme_minimal()

print(plot_importance)

# Guardar gráfico
output_path <- file.path(project_root, "output", "xgboost_tumor_stage_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# Gráfico de matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)
plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 6) +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Predicción de Tumor Stage",
       x = "Etapa Real", y = "Etapa Predicha") +
  theme_minimal()

print(plot_confusion)

output_path <- file.path(project_root, "output", "xgboost_tumor_stage_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# --- 9. GUARDAR MODELO ---
model_path <- file.path(project_root, "output", "xgboost_tumor_stage_model.rds")
saveRDS(modelo_xgb, model_path)
print(paste("Modelo guardado en:", model_path))

print("========================================")
print("RESUMEN FINAL:")
print(paste("Accuracy:", round(accuracy * 100, 2), "%"))
print(paste("Clases predichas:", length(unique(predicciones))))
print("")
print("Métricas por clase:")
print(conf_matrix$byClass[, c("Precision", "Recall", "F1")])
print("")
print("Nota: Este modelo usa solo información accesible:")
print("  - Edad, raza, estado menopáusico")
print("  - Características de imagen médica (30 features)")
print("  - Expresión génica (10 genes)")
print("  NO usa biomarcadores costosos ni biopsias invasivas")
print("¡Análisis completado!")
print("========================================")
