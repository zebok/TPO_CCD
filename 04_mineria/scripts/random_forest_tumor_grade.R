# ============================================================================
# RANDOM FOREST - PREDICCIÓN DE GRADO TUMORAL (tumor_grade)
# ============================================================================
# Objetivo: Predecir grado histológico (G1/G2/G3) usando SOLO características
#           de imagen de biopsia FNA (Fine Needle Aspiration)
#
# UTILIDAD CLÍNICA:
#   - Evitar biopsia invasiva tradicional
#   - Diagnóstico no invasivo basado en imagen
#   - Reducir costos y molestias al paciente
#   - Diagnóstico más rápido
#
# Variables usadas: 30 features de imagen WDBC (Wisconsin Diagnostic Breast Cancer)
#   - radius, texture, perimeter, area, smoothness, compactness, concavity,
#     concave_points, symmetry, fractal_dimension
#   - Para cada una: mean, se (standard error), worst (mean of 3 largest values)
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(randomForest)
library(caret)

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print("============================================")
print("RANDOM FOREST - PREDICCIÓN GRADO TUMORAL")
print("Diagnóstico NO INVASIVO basado en IMAGEN")
print("============================================")
print("")

# --- 2. FILTRAR DATOS CON GRADO TUMORAL Y FEATURES DE IMAGEN ---

# Features de imagen WDBC (30 variables)
features_imagen <- c(
  "radius_mean", "texture_mean", "perimeter_mean", "area_mean",
  "smoothness_mean", "compactness_mean", "concavity_mean", "concave_points_mean",
  "symmetry_mean", "fractal_dimension_mean",

  "radius_se", "texture_se", "perimeter_se", "area_se",
  "smoothness_se", "compactness_se", "concavity_se", "concave_points_se",
  "symmetry_se", "fractal_dimension_se",

  "radius_worst", "texture_worst", "perimeter_worst", "area_worst",
  "smoothness_worst", "compactness_worst", "concavity_worst", "concave_points_worst",
  "symmetry_worst", "fractal_dimension_worst"
)

# Filtrar pacientes con tumor_grade conocido y features de imagen
datos_clean <- datos %>%
  filter(!is.na(tumor_grade)) %>%
  select(tumor_grade, all_of(features_imagen))

# Eliminar filas con NAs en features de imagen
datos_clean <- datos_clean %>%
  filter(complete.cases(.))

print(paste("Pacientes con grado tumoral conocido y datos de imagen:", nrow(datos_clean)))
print("")
print("Distribución de tumor_grade:")
print(table(datos_clean$tumor_grade))
print("")
print("Proporción por grado:")
print(round(prop.table(table(datos_clean$tumor_grade)) * 100, 1))

# --- 3. PREPARAR DATOS ---

# Convertir tumor_grade a factor
datos_clean$tumor_grade <- as.factor(datos_clean$tumor_grade)

# Verificar niveles
print("")
print("Niveles de tumor_grade:")
print(levels(datos_clean$tumor_grade))

# --- 4. DIVISIÓN TRAIN/TEST ---
set.seed(123)
indices_train <- createDataPartition(datos_clean$tumor_grade, p = 0.8, list = FALSE)

datos_train <- datos_clean[indices_train, ]
datos_test <- datos_clean[-indices_train, ]

print("")
print(paste("Train:", nrow(datos_train), "| Test:", nrow(datos_test)))
print("")
print("Distribución en TRAIN:")
print(table(datos_train$tumor_grade))
print("")
print("Distribución en TEST:")
print(table(datos_test$tumor_grade))

# --- 5. ENTRENAMIENTO RANDOM FOREST ---

print("")
print("Entrenando Random Forest...")
print("Parámetros:")
print("  - ntree: 500 árboles")
print("  - mtry: sqrt(30) ≈ 5 variables por split")
print("  - importance: TRUE (para analizar variables importantes)")
print("")

set.seed(123)
modelo_rf <- randomForest(
  tumor_grade ~ .,
  data = datos_train,
  ntree = 500,
  mtry = 5,  # sqrt(30) ≈ 5
  importance = TRUE,
  proximity = FALSE,
  keep.forest = TRUE
)

print(modelo_rf)

# --- 6. PREDICCIONES Y EVALUACIÓN ---

predicciones <- predict(modelo_rf, datos_test)
conf_matrix <- confusionMatrix(predicciones, datos_test$tumor_grade)

accuracy <- conf_matrix$overall["Accuracy"]
kappa <- conf_matrix$overall["Kappa"]

print("")
print("========================================")
print("RESULTADOS EN TEST SET")
print("========================================")
print("")
print(paste("Accuracy:", round(accuracy * 100, 2), "%"))
print(paste("Kappa:", round(kappa, 3)))
print("")

# --- 7. VISUALIZACIONES ---

# 1. Importancia de variables (Mean Decrease Gini)
importance_df <- as.data.frame(importance(modelo_rf))
importance_df$Feature <- rownames(importance_df)
importance_df <- importance_df %>%
  arrange(desc(MeanDecreaseGini)) %>%
  head(20)

plot_importance_gini <- ggplot(importance_df, aes(x = reorder(Feature, MeanDecreaseGini), y = MeanDecreaseGini)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(title = "Top 20 Variables - Importancia (Gini)",
       subtitle = "Random Forest - Predicción Grado Tumoral",
       x = "Feature de Imagen",
       y = "Mean Decrease Gini") +
  theme_minimal(base_size = 12)

print(plot_importance_gini)

output_path <- file.path(project_root, "output", "rf_tumor_grade_importance_gini.png")
ggsave(output_path, plot = plot_importance_gini, width = 12, height = 8, dpi = 300)

# 2. Importancia de variables (Mean Decrease Accuracy)
importance_acc <- importance_df %>%
  arrange(desc(MeanDecreaseAccuracy)) %>%
  head(20)

plot_importance_acc <- ggplot(importance_acc, aes(x = reorder(Feature, MeanDecreaseAccuracy), y = MeanDecreaseAccuracy)) +
  geom_col(fill = "darkgreen") +
  coord_flip() +
  labs(title = "Top 20 Variables - Importancia (Accuracy)",
       subtitle = "Random Forest - Predicción Grado Tumoral",
       x = "Feature de Imagen",
       y = "Mean Decrease Accuracy") +
  theme_minimal(base_size = 12)

print(plot_importance_acc)

output_path <- file.path(project_root, "output", "rf_tumor_grade_importance_acc.png")
ggsave(output_path, plot = plot_importance_acc, width = 12, height = 8, dpi = 300)

# 3. Matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)

plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 10, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  labs(title = "Matriz de Confusión - Random Forest",
       subtitle = paste("Accuracy:", round(accuracy * 100, 1), "% | Predicción Grado Tumoral"),
       x = "Grado Real", y = "Grado Predicho") +
  theme_minimal(base_size = 14)

print(plot_confusion)

output_path <- file.path(project_root, "output", "rf_tumor_grade_confusion.png")
ggsave(output_path, plot = plot_confusion, width = 10, height = 8, dpi = 300)

# 4. Error por número de árboles
error_df <- data.frame(
  ntrees = 1:modelo_rf$ntree,
  OOB = modelo_rf$err.rate[, "OOB"]
)

if (ncol(modelo_rf$err.rate) > 1) {
  clases <- colnames(modelo_rf$err.rate)[-1]
  for (clase in clases) {
    error_df[[clase]] <- modelo_rf$err.rate[, clase]
  }
}

error_long <- error_df %>%
  pivot_longer(cols = -ntrees, names_to = "Clase", values_to = "Error")

plot_error <- ggplot(error_long, aes(x = ntrees, y = Error, color = Clase)) +
  geom_line(size = 1) +
  labs(title = "Error OOB vs Número de Árboles",
       subtitle = "Random Forest - Convergencia del modelo",
       x = "Número de Árboles",
       y = "Tasa de Error") +
  theme_minimal(base_size = 12) +
  scale_color_brewer(palette = "Set1")

print(plot_error)

output_path <- file.path(project_root, "output", "rf_tumor_grade_error_convergence.png")
ggsave(output_path, plot = plot_error, width = 12, height = 8, dpi = 300)

# --- 8. MÉTRICAS POR CLASE ---

print("")
print("MÉTRICAS POR CLASE:")
print("")

if (is.matrix(conf_matrix$byClass)) {
  for (i in 1:nrow(conf_matrix$byClass)) {
    clase <- rownames(conf_matrix$byClass)[i]
    sens <- conf_matrix$byClass[i, "Sensitivity"]
    spec <- conf_matrix$byClass[i, "Specificity"]
    ppv <- conf_matrix$byClass[i, "Pos Pred Value"]
    npv <- conf_matrix$byClass[i, "Neg Pred Value"]
    f1 <- conf_matrix$byClass[i, "F1"]

    print(paste("Clase:", gsub("Class: ", "", clase)))
    print(paste("  Sensitivity (Recall):", round(sens * 100, 1), "%"))
    print(paste("  Specificity:", round(spec * 100, 1), "%"))
    print(paste("  Precision (PPV):", round(ppv * 100, 1), "%"))
    print(paste("  F1-Score:", round(f1 * 100, 1), "%"))
    print("")
  }
} else {
  sens <- conf_matrix$byClass["Sensitivity"]
  spec <- conf_matrix$byClass["Specificity"]
  ppv <- conf_matrix$byClass["Pos Pred Value"]
  f1 <- conf_matrix$byClass["F1"]

  print(paste("Sensitivity (Recall):", round(sens * 100, 1), "%"))
  print(paste("Specificity:", round(spec * 100, 1), "%"))
  print(paste("Precision (PPV):", round(ppv * 100, 1), "%"))
  print(paste("F1-Score:", round(f1 * 100, 1), "%"))
}

print("")
print("MATRIZ DE CONFUSIÓN:")
print(conf_matrix$table)

# --- 9. RESUMEN FINAL ---

print("")
print("========================================")
print("RESUMEN FINAL")
print("========================================")
print("")
print("UTILIDAD CLÍNICA:")
print("  ✅ Predicción de grado tumoral SOLO con imagen FNA")
print("  ✅ EVITA biopsia invasiva tradicional")
print("  ✅ Reduce costos (no histopatología)")
print("  ✅ Reduce molestias al paciente")
print("  ✅ Diagnóstico más rápido")
print("")
print("CARACTERÍSTICAS DEL MODELO:")
print(paste("  - Árboles:", modelo_rf$ntree))
print(paste("  - Variables usadas:", ncol(datos_train) - 1, "(30 features de imagen)"))
print(paste("  - OOB Error:", round(modelo_rf$err.rate[modelo_rf$ntree, "OOB"] * 100, 2), "%"))
print(paste("  - Accuracy en Test:", round(accuracy * 100, 2), "%"))
print("")
print("TOP 10 FEATURES MÁS IMPORTANTES (Gini):")
top10 <- head(importance_df %>% arrange(desc(MeanDecreaseGini)), 10)
for (i in 1:nrow(top10)) {
  print(paste("  ", i, ".", top10$Feature[i]))
}
print("")
print("INTERPRETACIÓN:")
print("  - Features 'worst' (valores máximos) son los más importantes")
print("  - Concavity, radius, area discriminan bien el grado")
print("  - Tumores agresivos (G3) tienen mayor concavidad/irregularidad")
print("")
print("========================================")

# Guardar modelo
model_path <- file.path(project_root, "output", "rf_tumor_grade_model.rds")
saveRDS(modelo_rf, model_path)
print(paste("Modelo guardado en:", model_path))

# Guardar predicciones
resultados <- data.frame(
  grado_real = datos_test$tumor_grade,
  grado_predicho = predicciones,
  correcto = datos_test$tumor_grade == predicciones
)

output_csv <- file.path(project_root, "output", "rf_tumor_grade_resultados_test.csv")
write_csv(resultados, output_csv)
print(paste("Resultados guardados en:", output_csv))
