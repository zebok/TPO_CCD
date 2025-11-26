# ============================================================================
# XGBOOST - PREDICCIÓN DE TUMOR_STAGE CON BIOPSIA FNA (BINARIO)
# ============================================================================
# Objetivo: Predecir si el tumor es Early (Stage I-II) o Advanced (Stage III-IV)
#           usando SOLO:
#           - Edad, raza (demográficos mínimos)
#           - Características de biopsia FNA (30 variables: radius, texture, etc.)
#           SIN genes, SIN biomarcadores costosos
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

# 3.1.5. CREAR VARIABLE BINARIA: Early vs Advanced
# Early: Stage I y II
# Advanced: Stage III y IV
datos_clean <- datos_clean %>%
  mutate(stage_binary = case_when(
    tumor_stage %in% c("Stage I", "Stage II") ~ "Early",
    tumor_stage %in% c("Stage III", "Stage IV") ~ "Advanced",
    TRUE ~ NA_character_
  ))

print("Distribución de stage_binary:")
print(table(datos_clean$stage_binary, useNA = "always"))

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
  "stage_binary",

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
  "gender",
  "menopausal_state",  # Excluido según requisito

  # GENES (MUY COSTOSOS - EXCLUIDOS)
  "esr1_expression",
  "pgr_expression",
  "erbb2_expression",
  "mki67_expression",
  "tp53_expression",
  "brca1_expression",
  "brca2_expression",
  "pik3ca_expression",
  "pten_expression",
  "akt1_expression"
)

# Variables predictoras (todas menos las eliminadas)
# USAREMOS SOLO: edad, raza, características de biopsia FNA (30)
predictores <- datos_clean %>%
  dplyr::select(-any_of(variables_a_eliminar))

# Verificar qué variables tenemos
print("Variables disponibles:")
print(names(predictores))

# Variable objetivo (BINARIA)
objetivo <- datos_clean$stage_binary

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
print(paste("Clases en stage_binary:", length(unique(objetivo)), "- Early vs Advanced"))

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

# Parámetros del modelo (CLASIFICACIÓN BINARIA)
params <- list(
  objective = "binary:logistic",         # Clasificación binaria
  eta = 0.05,                            # Learning rate
  max_depth = 8,                         # Profundidad del árbol
  min_child_weight = 3,                  # Evitar overfitting
  subsample = 0.8,                       # % de muestras por árbol
  colsample_bytree = 0.8,                # % de features por árbol
  gamma = 1,                             # Regularización
  eval_metric = "logloss"                # Métrica para clasificación binaria
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

# Predicciones en test (clasificación binaria devuelve probabilidades)
predicciones_prob <- predict(modelo_xgb, dtest)
predicciones_numeric <- ifelse(predicciones_prob > 0.5, 1, 0)
predicciones <- clases_nombres[predicciones_numeric + 1]
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
output_path <- file.path(project_root, "output", "xgboost_tumor_stage_sin_genes_importance.png")
ggsave(output_path, plot = plot_importance, width = 12, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# Gráfico de matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)
plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 8, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Early vs Advanced Stage",
       x = "Stage Real", y = "Stage Predicho") +
  theme_minimal(base_size = 14)

print(plot_confusion)

output_path <- file.path(project_root, "output", "xgboost_tumor_stage_sin_genes_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))

# --- 9. GUARDAR MODELO ---
model_path <- file.path(project_root, "output", "xgboost_tumor_stage_sin_genes_model.rds")
saveRDS(modelo_xgb, model_path)
print(paste("Modelo guardado en:", model_path))

print("========================================")
print("RESUMEN FINAL - CLASIFICACIÓN BINARIA")
print("========================================")
print(paste("Accuracy:", round(accuracy * 100, 2), "%"))
print("")
print("Métricas:")
print(paste("Sensitivity (Recall):", round(conf_matrix$byClass["Sensitivity"] * 100, 2), "%"))
print(paste("Specificity:", round(conf_matrix$byClass["Specificity"] * 100, 2), "%"))
print(paste("Precision:", round(conf_matrix$byClass["Precision"] * 100, 2), "%"))
print(paste("F1-Score:", round(conf_matrix$byClass["F1"] * 100, 2), "%"))
print("")
print("Matriz de Confusión:")
print(conf_matrix$table)
print("")
print("Nota: Este modelo usa SOLO:")
print("  ✅ Edad, raza (demográficos básicos)")
print("  ✅ Características de biopsia FNA (30 features de WDBC)")
print("       - radius, texture, perimeter, area, smoothness, etc.")
print("  ❌ NO usa expresión génica (muy costosa)")
print("  ❌ NO usa biomarcadores (ER, HER2, PR)")
print("  ❌ NO usa estado menopáusico")
print("  ❌ NO usa características tumorales invasivas (grade, size, lymph nodes)")
print("")
print("Clasifica tumores en:")
print("  - Early: Stage I y II (menos agresivos)")
print("  - Advanced: Stage III y IV (más agresivos)")
print("¡Análisis completado!")
print("========================================")
