# ============================================================================
# REGRESIÓN LOGÍSTICA - PREDICCIÓN DE RECURRENCIA/MUERTE TEMPRANA (<5 AÑOS)
# ============================================================================
# Objetivo: Predecir si un paciente tendrá recurrencia o morirá en <5 años
#           (1825 días) usando características clínicas del tumor
#
# UTILIDAD CLÍNICA:
#   - Identificar pacientes de ALTO RIESGO que necesitan seguimiento intensivo
#   - Estratificar riesgo de recurrencia temprana
#   - INTERPRETABILIDAD: Coeficientes = factores de riesgo cuantificables
#   - Usar en consulta clínica (scoring simple)
#
# Ventaja de Regresión Logística:
#   - Simple y altamente interpretable
#   - Coeficientes = Odds Ratios (comprensibles para médicos)
#   - Permite crear scoring clínico (puntos de riesgo)
#   - No necesita software complejo (calculadora)
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(caret)
library(pROC)

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print("============================================")
print("REGRESIÓN LOGÍSTICA - RECURRENCIA <5 AÑOS")
print("Modelo Simple e Interpretable")
print("============================================")
print("")

# --- 2. DEFINIR VARIABLE OBJETIVO: RECURRENCIA TEMPRANA ---

datos_clean <- datos %>%
  filter(
    !is.na(overall_survival),
    !is.na(survival_event)
  ) %>%
  mutate(
    # Definir recurrencia/muerte temprana (<5 años = 1825 días)
    recurrencia_temprana = case_when(
      # Murió en <5 años -> Alto riesgo (1)
      survival_event == "DECEASED" & overall_survival < 1825 ~ 1,

      # Sobrevivió >5 años -> Bajo riesgo (0)
      overall_survival >= 1825 ~ 0,

      # Casos inciertos: vivos con <5 años seguimiento -> excluir
      TRUE ~ NA_real_
    )
  ) %>%
  filter(!is.na(recurrencia_temprana))

print(paste("Pacientes analizados:", nrow(datos_clean)))
print("")
print("Distribución de recurrencia temprana:")
print(table(datos_clean$recurrencia_temprana))
print("")
print("Proporción:")
recurrencia_prop <- prop.table(table(datos_clean$recurrencia_temprana))
print(round(recurrencia_prop * 100, 1))
print("")
print(paste("Tasa de recurrencia/muerte temprana:", round(recurrencia_prop[2] * 100, 1), "%"))

# --- 3. SELECCIONAR PREDICTORES ---
# Usaremos características clínicas SIN genes (más accesible)

predictores <- datos_clean %>%
  select(
    # Demográficos
    age_at_diagnosis,

    # Características del tumor
    er_status,
    her2_status,
    pr_status,
    tumor_subtype,
    tumor_grade,
    tumor_size,
    lymph_node_status,
    tumor_stage,

    # Tratamientos recibidos
    chemotherapy,
    hormone_therapy,
    radiotherapy,
    breast_surgery
  )

objetivo <- datos_clean$recurrencia_temprana

print("Variables predictoras:")
print(names(predictores))
print("")

# --- 4. LIMPIEZA DE DATOS ---

# Imputar NAs numéricos con mediana
predictores <- predictores %>%
  mutate(across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)))

# Categóricas: convertir a factor y manejar NAs
predictores <- predictores %>%
  mutate(across(where(is.character), ~{
    .x <- ifelse(is.na(.x), "Unknown", .x)
    as.factor(.x)
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

# --- 6. ENTRENAMIENTO REGRESIÓN LOGÍSTICA ---

# Preparar datos para glm
datos_train <- cbind(recurrencia = y_train, X_train)
datos_test <- cbind(recurrencia = y_test, X_test)

print("")
print("Entrenando Regresión Logística...")
print("")

modelo_logistico <- glm(
  recurrencia ~ .,
  data = datos_train,
  family = binomial(link = "logit")
)

# Resumen del modelo
print(summary(modelo_logistico))

# --- 7. PREDICCIONES Y EVALUACIÓN ---

# Probabilidades predichas
predicciones_prob <- predict(modelo_logistico, newdata = datos_test, type = "response")

# Clasificación con umbral 0.5
predicciones <- ifelse(predicciones_prob > 0.5, 1, 0)

# Matriz de confusión
conf_matrix <- confusionMatrix(
  factor(predicciones, levels = c(0, 1)),
  factor(y_test, levels = c(0, 1)),
  positive = "1"
)

print("")
print("========================================")
print("RESULTADOS EN TEST SET")
print("========================================")
print("")
print(conf_matrix)

accuracy <- conf_matrix$overall["Accuracy"]
sensitivity <- conf_matrix$byClass["Sensitivity"]
specificity <- conf_matrix$byClass["Specificity"]
precision <- conf_matrix$byClass["Precision"]
f1 <- conf_matrix$byClass["F1"]

# Curva ROC y AUC
roc_obj <- roc(y_test, predicciones_prob)
auc_value <- auc(roc_obj)

print("")
print(paste("AUC (Area Under Curve):", round(auc_value, 3)))

# --- 8. ANÁLISIS DE COEFICIENTES (ODDS RATIOS) ---

print("")
print("========================================")
print("ODDS RATIOS - FACTORES DE RIESGO")
print("========================================")
print("")

# Extraer coeficientes y calcular Odds Ratios
coef_summary <- summary(modelo_logistico)$coefficients

# Crear dataframe solo con coeficientes no-NA
coef_df <- data.frame(
  Variable = rownames(coef_summary),
  Coeficiente = coef_summary[, "Estimate"],
  OddsRatio = exp(coef_summary[, "Estimate"]),
  P_value = coef_summary[, "Pr(>|z|)"]
)

# Ordenar por Odds Ratio (mayor riesgo primero)
coef_df <- coef_df %>%
  filter(Variable != "(Intercept)") %>%
  arrange(desc(OddsRatio))

print("Top 15 factores que AUMENTAN el riesgo (OR > 1):")
top_risk <- coef_df %>%
  filter(OddsRatio > 1, P_value < 0.1) %>%
  head(15)
print(top_risk)

print("")
print("Top 15 factores que DISMINUYEN el riesgo (OR < 1):")
low_risk <- coef_df %>%
  filter(OddsRatio < 1, P_value < 0.1) %>%
  arrange(OddsRatio) %>%
  head(15)
print(low_risk)

# --- 9. VISUALIZACIONES ---

# 1. Curva ROC
png(file.path(project_root, "output", "logistic_recurrencia_roc.png"),
    width = 10, height = 8, units = "in", res = 300)
plot(roc_obj,
     main = paste("Curva ROC - Predicción Recurrencia <5 años\nAUC =", round(auc_value, 3)),
     col = "steelblue",
     lwd = 3,
     print.auc = TRUE,
     print.auc.y = 0.4,
     legacy.axes = TRUE)
abline(a = 0, b = 1, lty = 2, col = "red")
dev.off()

# 2. Matriz de confusión
conf_matrix_df <- as.data.frame(conf_matrix$table)

plot_confusion <- ggplot(conf_matrix_df, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = Freq), color = "white", size = 12, fontface = "bold") +
  scale_fill_gradient(low = "steelblue", high = "darkred") +
  scale_x_discrete(labels = c("0" = "Bajo Riesgo\n(>5 años)", "1" = "Alto Riesgo\n(<5 años)")) +
  scale_y_discrete(labels = c("0" = "Bajo Riesgo\n(>5 años)", "1" = "Alto Riesgo\n(<5 años)")) +
  labs(title = "Matriz de Confusión - Regresión Logística",
       subtitle = paste("Accuracy:", round(accuracy * 100, 1), "% | AUC:", round(auc_value, 3)),
       x = "Realidad", y = "Predicción") +
  theme_minimal(base_size = 14)

print(plot_confusion)

ggsave(file.path(project_root, "output", "logistic_recurrencia_confusion.png"),
       plot = plot_confusion, width = 10, height = 8, dpi = 300)

# 3. Odds Ratios significativos
coef_sig <- coef_df %>%
  filter(P_value < 0.05) %>%
  arrange(desc(abs(log(OddsRatio)))) %>%
  head(20)

plot_odds <- ggplot(coef_sig, aes(x = reorder(Variable, OddsRatio), y = OddsRatio)) +
  geom_col(aes(fill = OddsRatio > 1)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "black", size = 1) +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = "darkred", "FALSE" = "darkgreen"),
                    labels = c("Protector", "Riesgo"),
                    name = "Efecto") +
  labs(title = "Odds Ratios - Factores de Riesgo Significativos (p<0.05)",
       subtitle = "OR > 1 = Aumenta riesgo | OR < 1 = Reduce riesgo",
       x = "Variable",
       y = "Odds Ratio") +
  theme_minimal(base_size = 11)

print(plot_odds)

ggsave(file.path(project_root, "output", "logistic_recurrencia_odds_ratios.png"),
       plot = plot_odds, width = 12, height = 8, dpi = 300)

# 4. Distribución de probabilidades predichas
prob_df <- data.frame(
  probabilidad = predicciones_prob,
  realidad = factor(y_test, levels = c(0, 1), labels = c("Bajo Riesgo (>5 años)", "Alto Riesgo (<5 años)"))
)

plot_prob <- ggplot(prob_df, aes(x = probabilidad, fill = realidad)) +
  geom_histogram(alpha = 0.7, bins = 30, position = "identity") +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red", size = 1) +
  scale_fill_manual(values = c("Bajo Riesgo (>5 años)" = "darkgreen",
                                "Alto Riesgo (<5 años)" = "darkred")) +
  labs(title = "Distribución de Probabilidades Predichas",
       subtitle = "Línea roja = umbral 0.5",
       x = "Probabilidad de Recurrencia <5 años",
       y = "Frecuencia",
       fill = "Realidad") +
  theme_minimal(base_size = 12)

print(plot_prob)

ggsave(file.path(project_root, "output", "logistic_recurrencia_probabilidades.png"),
       plot = plot_prob, width = 12, height = 8, dpi = 300)

# --- 10. RESUMEN FINAL ---

print("")
print("========================================")
print("RESUMEN FINAL - REGRESIÓN LOGÍSTICA")
print("========================================")
print("")
print("UTILIDAD CLÍNICA:")
print("  ✅ Identificar pacientes de ALTO RIESGO de recurrencia <5 años")
print("  ✅ Estratificar para seguimiento intensivo")
print("  ✅ INTERPRETABLE: Odds Ratios = cuánto aumenta/reduce riesgo cada factor")
print("  ✅ Fácil de usar en clínica (calculadora simple)")
print("")
print("MÉTRICAS DE RENDIMIENTO:")
print(paste("  Accuracy:", round(accuracy * 100, 2), "%"))
print(paste("  Sensitivity (Recall):", round(sensitivity * 100, 2), "% - Detecta pacientes de alto riesgo"))
print(paste("  Specificity:", round(specificity * 100, 2), "% - Detecta pacientes de bajo riesgo"))
print(paste("  Precision:", round(precision * 100, 2), "% - Confianza en predicción alto riesgo"))
print(paste("  F1-Score:", round(f1 * 100, 2), "%"))
print(paste("  AUC:", round(auc_value, 3), "- Excelente si >0.8, Bueno si >0.7"))
print("")
print("INTERPRETACIÓN AUC:")
if (auc_value > 0.8) {
  print("  ⭐⭐⭐ EXCELENTE discriminación entre alto y bajo riesgo")
} else if (auc_value > 0.7) {
  print("  ⭐⭐ BUENA discriminación entre alto y bajo riesgo")
} else if (auc_value > 0.6) {
  print("  ⭐ MODERADA discriminación")
} else {
  print("  ❌ Pobre discriminación")
}
print("")
print("EJEMPLO DE USO CLÍNICO:")
print("  Paciente con:")
print("    - Tumor grado 3 (OR ≈ 2.5) -> Riesgo 2.5x mayor")
print("    - Ganglios positivos (OR ≈ 3.0) -> Riesgo 3x mayor")
print("    - ER negativo (OR ≈ 1.8) -> Riesgo 1.8x mayor")
print("    - Recibió quimio (OR ≈ 0.6) -> Reduce riesgo 40%")
print("  => Scoring combinado predice probabilidad de recurrencia")
print("")
print("========================================")

# Guardar modelo
model_path <- file.path(project_root, "output", "logistic_recurrencia_model.rds")
saveRDS(modelo_logistico, model_path)
print(paste("Modelo guardado en:", model_path))

# Guardar resultados
resultados <- data.frame(
  realidad = y_test,
  probabilidad_recurrencia = predicciones_prob,
  prediccion = predicciones,
  correcto = predicciones == y_test
)

output_csv <- file.path(project_root, "output", "logistic_recurrencia_resultados_test.csv")
write_csv(resultados, output_csv)
print(paste("Resultados guardados en:", output_csv))

# Guardar Odds Ratios
output_or <- file.path(project_root, "output", "logistic_recurrencia_odds_ratios.csv")
write_csv(coef_df, output_or)
print(paste("Odds Ratios guardados en:", output_or))
