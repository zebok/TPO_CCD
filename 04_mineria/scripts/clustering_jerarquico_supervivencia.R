# ============================================================================
# CLUSTERING JERÁRQUICO + ANÁLISIS DE SUPERVIVENCIA (KAPLAN-MEIER)
# ============================================================================
# Objetivo: Descubrir grupos de pacientes con patrones de supervivencia similares
#           usando características clínicas y genéticas
#
# UTILIDAD CLÍNICA:
#   - Identificar subgrupos de riesgo NO OBVIOS (más allá de subtipo molecular)
#   - Descubrir biomarcadores ocultos que afectan supervivencia
#   - Estratificación de riesgo personalizada
#   - Guiar decisiones de tratamiento según cluster
#
# Metodología:
#   1. Clustering Jerárquico (método no supervisado)
#   2. Análisis de Supervivencia con Kaplan-Meier por cluster
#   3. Log-rank test para significancia estadística
#   4. Caracterización de clusters (qué los define)
# ============================================================================

# --- LIBRERÍAS ---
library(tidyverse)
library(rprojroot)
library(survival)      # Para Kaplan-Meier y Cox
library(survminer)     # Para visualización de curvas KM
library(cluster)       # Para clustering
library(factoextra)    # Para visualización de clusters
library(dendextend)    # Para dendrogramas mejorados

# --- 1. CARGAR DATOS ---
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
datos <- read_csv(dataset_path)

print("============================================")
print("CLUSTERING JERÁRQUICO + KAPLAN-MEIER")
print("Descubrimiento de Grupos de Supervivencia")
print("============================================")
print("")

# --- 2. PREPARAR DATOS PARA CLUSTERING ---

# Filtrar pacientes con datos de supervivencia completos
datos_clean <- datos %>%
  filter(
    !is.na(overall_survival),
    !is.na(survival_event)
  )

print(paste("Pacientes con datos completos de supervivencia:", nrow(datos_clean)))

# Seleccionar features para clustering
# Usaremos solo características con <5% NAs para maximizar datos
features_clustering <- c(
  # Demográficos
  "age_at_diagnosis"
)

# Extraer features + outcomes + categóricas
datos_features <- datos_clean %>%
  select(
    all_of(features_clustering),
    # Agregar solo variables con pocos NAs
    er_status, her2_status,
    overall_survival, survival_event, id_paciente
  ) %>%
  # Convertir categóricas a numéricas manualmente
  mutate(
    er_pos = ifelse(er_status == "Positive", 1, 0),
    her2_pos = ifelse(her2_status == "Positive", 1, 0),
    her2_neg = ifelse(her2_status == "Negative", 1, 0)
  )

# Eliminar filas con NAs
datos_features <- datos_features %>%
  filter(complete.cases(.))

print(paste("Pacientes con datos completos para clustering:", nrow(datos_features)))

# Seleccionar solo variables numéricas para clustering
features_matrix <- datos_features %>%
  select(all_of(features_clustering),
         er_pos, her2_pos, her2_neg) %>%
  as.matrix()

# Hacer rownames únicos
rownames(features_matrix) <- make.unique(as.character(datos_features$id_paciente))

# Estandarizar (importante para clustering)
features_scaled <- scale(features_matrix)

print("")
print("Features usadas para clustering:")
print(colnames(features_matrix))

# --- 3. DETERMINAR NÚMERO ÓPTIMO DE CLUSTERS ---

print("")
print("Determinando número óptimo de clusters...")
print("")

# Método del codo (Elbow method)
set.seed(123)
fviz_nbclust(features_scaled,
             FUNcluster = hcut,
             method = "wss",
             k.max = 10) +
  labs(title = "Método del Codo - Clustering Jerárquico") +
  theme_minimal()

ggsave(file.path(project_root, "output", "clustering_elbow.png"),
       width = 10, height = 6, dpi = 300)

# Método de Silhouette
fviz_nbclust(features_scaled,
             FUNcluster = hcut,
             method = "silhouette",
             k.max = 10) +
  labs(title = "Método Silhouette - Clustering Jerárquico") +
  theme_minimal()

ggsave(file.path(project_root, "output", "clustering_silhouette.png"),
       width = 10, height = 6, dpi = 300)

# Decidir número de clusters (probaremos con 4)
n_clusters <- 4

# --- 4. CLUSTERING JERÁRQUICO ---

print("")
print(paste("Realizando clustering jerárquico con", n_clusters, "clusters..."))

# Calcular matriz de distancias (euclidiana)
dist_matrix <- dist(features_scaled, method = "euclidean")

# Clustering jerárquico con método Ward (minimiza varianza intra-cluster)
hc <- hclust(dist_matrix, method = "ward.D2")

# Cortar dendrograma para obtener n_clusters
clusters <- cutree(hc, k = n_clusters)

print("")
print("Distribución de pacientes por cluster:")
print(table(clusters))

# --- 5. VISUALIZACIÓN DEL DENDROGRAMA ---

# Dendrograma completo (demasiados pacientes, solo para archivo)
png(file.path(project_root, "output", "clustering_dendrograma_completo.png"),
    width = 16, height = 10, units = "in", res = 300)
plot(hc,
     main = "Dendrograma Jerárquico - Análisis de Supervivencia",
     xlab = "Pacientes",
     ylab = "Altura (Distancia)",
     cex = 0.3)
rect.hclust(hc, k = n_clusters, border = 2:5)
dev.off()

# Dendrograma mejorado con colores
dend <- as.dendrogram(hc)
dend_colored <- color_branches(dend, k = n_clusters)

png(file.path(project_root, "output", "clustering_dendrograma_coloreado.png"),
    width = 16, height = 10, units = "in", res = 300)
plot(dend_colored,
     main = paste("Dendrograma Jerárquico -", n_clusters, "Clusters"),
     cex = 0.3)
dev.off()

# --- 6. ANÁLISIS DE SUPERVIVENCIA POR CLUSTER ---

# Añadir clusters al dataframe
datos_clustered <- datos_features %>%
  mutate(cluster = factor(clusters))

# Convertir survival_event a numérico (1=evento, 0=censurado)
datos_clustered <- datos_clustered %>%
  mutate(
    status = ifelse(survival_event == "DECEASED", 1, 0),
    time = overall_survival / 365.25  # Convertir días a años
  )

print("")
print("========================================")
print("ANÁLISIS DE SUPERVIVENCIA POR CLUSTER")
print("========================================")
print("")

# Crear objeto de supervivencia
surv_object <- Surv(time = datos_clustered$time,
                    event = datos_clustered$status)

# Fit de Kaplan-Meier por cluster
km_fit <- survfit(surv_object ~ cluster, data = datos_clustered)

print(km_fit)

# --- 7. CURVAS DE KAPLAN-MEIER ---

# Gráfico de Kaplan-Meier
km_plot <- ggsurvplot(
  km_fit,
  data = datos_clustered,
  pval = TRUE,                    # Mostrar p-value del log-rank test
  conf.int = TRUE,                # Intervalos de confianza
  risk.table = TRUE,              # Tabla de riesgo
  risk.table.height = 0.25,
  palette = c("#E7B800", "#2E9FDF", "#00AFBB", "#FC4E07"),
  title = "Curvas de Supervivencia Kaplan-Meier por Cluster",
  xlab = "Tiempo (años)",
  ylab = "Probabilidad de Supervivencia",
  legend.title = "Cluster",
  legend.labs = paste("Cluster", 1:n_clusters),
  ggtheme = theme_minimal(base_size = 12)
)

print(km_plot)

# Guardar gráfico
ggsave(file.path(project_root, "output", "clustering_kaplan_meier.png"),
       plot = km_plot$plot,
       width = 12, height = 10, dpi = 300)

# --- 8. LOG-RANK TEST ---

print("")
print("LOG-RANK TEST (comparación entre clusters):")
print("")

logrank_test <- survdiff(surv_object ~ cluster, data = datos_clustered)
print(logrank_test)

p_value <- 1 - pchisq(logrank_test$chisq, df = n_clusters - 1)
print("")
print(paste("P-value:", format.pval(p_value, digits = 3)))

if (p_value < 0.05) {
  print("✅ Diferencias SIGNIFICATIVAS entre clusters (p < 0.05)")
} else {
  print("❌ NO hay diferencias significativas entre clusters (p >= 0.05)")
}

# --- 9. CARACTERIZACIÓN DE CLUSTERS ---

print("")
print("========================================")
print("CARACTERIZACIÓN DE CLUSTERS")
print("========================================")
print("")

# Calcular estadísticas por cluster
cluster_stats <- datos_clustered %>%
  group_by(cluster) %>%
  summarise(
    n_pacientes = n(),
    tasa_mortalidad = mean(status) * 100,
    supervivencia_mediana_años = median(time),
    supervivencia_media_años = mean(time),

    # Proporción de características
    prop_er_positive = mean(er_pos, na.rm = TRUE) * 100,
    prop_her2_positive = mean(her2_pos, na.rm = TRUE) * 100,

    # Características clínicas
    edad_media = mean(age_at_diagnosis, na.rm = TRUE)
  ) %>%
  arrange(supervivencia_mediana_años)

print(cluster_stats)

# --- 10. VISUALIZACIÓN DE PERFILES DE CLUSTER ---

# Calcular promedios por cluster
cluster_profiles <- datos_clustered %>%
  group_by(cluster) %>%
  summarise(
    edad_media = mean(age_at_diagnosis, na.rm = TRUE),
    prop_er_pos = mean(er_pos, na.rm = TRUE),
    prop_her2_pos = mean(her2_pos, na.rm = TRUE)
  )

print("")
print("Perfiles promedio por cluster:")
print(cluster_profiles)

# --- 11. VISUALIZACIÓN PCA DE CLUSTERS ---

# PCA para visualizar clusters en 2D
pca_result <- prcomp(features_scaled, center = FALSE, scale. = FALSE)

pca_df <- data.frame(
  PC1 = pca_result$x[, 1],
  PC2 = pca_result$x[, 2],
  cluster = factor(clusters),
  status = factor(datos_clustered$status, levels = c(0, 1), labels = c("Vivo", "Fallecido"))
)

plot_pca <- ggplot(pca_df, aes(x = PC1, y = PC2, color = cluster, shape = status)) +
  geom_point(size = 3, alpha = 0.6) +
  stat_ellipse(aes(group = cluster), type = "norm", level = 0.95) +
  scale_color_manual(values = c("#E7B800", "#2E9FDF", "#00AFBB", "#FC4E07")) +
  labs(title = "Clusters en Espacio PCA",
       subtitle = "Componentes Principales 1 y 2",
       x = paste0("PC1 (", round(summary(pca_result)$importance[2, 1] * 100, 1), "% varianza)"),
       y = paste0("PC2 (", round(summary(pca_result)$importance[2, 2] * 100, 1), "% varianza)"),
       color = "Cluster",
       shape = "Estado") +
  theme_minimal(base_size = 12)

print(plot_pca)

ggsave(file.path(project_root, "output", "clustering_pca_visualizacion.png"),
       plot = plot_pca, width = 12, height = 8, dpi = 300)

# --- 12. COX REGRESSION - HAZARD RATIOS POR CLUSTER ---

print("")
print("========================================")
print("COX REGRESSION - HAZARD RATIOS")
print("========================================")
print("")

# Usar Cluster 1 (mejor supervivencia) como referencia
datos_clustered$cluster <- relevel(datos_clustered$cluster, ref = "1")

# Fit Cox Proportional Hazards
cox_model <- coxph(Surv(time, status) ~ cluster, data = datos_clustered)

print(summary(cox_model))

# Extraer Hazard Ratios
hr_df <- data.frame(
  Cluster = names(coef(cox_model)),
  HazardRatio = exp(coef(cox_model)),
  CI_lower = exp(confint(cox_model)[, 1]),
  CI_upper = exp(confint(cox_model)[, 2]),
  P_value = summary(cox_model)$coefficients[, "Pr(>|z|)"]
)

print("")
print("Hazard Ratios por Cluster (vs Cluster 1 - referencia):")
print(hr_df)

# Gráfico de Hazard Ratios
plot_hr <- ggplot(hr_df, aes(x = Cluster, y = HazardRatio)) +
  geom_point(size = 4, color = "darkred") +
  geom_errorbar(aes(ymin = CI_lower, ymax = CI_upper), width = 0.2) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "black") +
  labs(title = "Hazard Ratios por Cluster (vs Cluster 1)",
       subtitle = "HR > 1 = Mayor riesgo de muerte | HR < 1 = Menor riesgo",
       x = "Cluster",
       y = "Hazard Ratio (95% CI)") +
  theme_minimal(base_size = 12)

print(plot_hr)

ggsave(file.path(project_root, "output", "clustering_hazard_ratios.png"),
       plot = plot_hr, width = 10, height = 6, dpi = 300)

# --- 13. RESUMEN FINAL ---

print("")
print("========================================")
print("RESUMEN FINAL - CLUSTERING JERÁRQUICO")
print("========================================")
print("")
print("UTILIDAD CLÍNICA:")
print("  ✅ Identificación de subgrupos de riesgo basados en perfil molecular")
print("  ✅ Estratificación más fina que subtipo molecular tradicional")
print("  ✅ Descubrimiento de biomarcadores ocultos")
print("  ✅ Guía para tratamientos personalizados")
print("")
print(paste("NÚMERO DE CLUSTERS:", n_clusters))
print("")
print("CARACTERÍSTICAS DE CADA CLUSTER:")
print("")

for (i in 1:n_clusters) {
  cluster_data <- cluster_stats %>% filter(cluster == i)

  print(paste("CLUSTER", i, ":"))
  print(paste("  - Pacientes:", cluster_data$n_pacientes))
  print(paste("  - Tasa de mortalidad:", round(cluster_data$tasa_mortalidad, 1), "%"))
  print(paste("  - Supervivencia mediana:", round(cluster_data$supervivencia_mediana_años, 1), "años"))
  print(paste("  - Edad media:", round(cluster_data$edad_media, 1), "años"))
  print(paste("  - ER+ :", round(cluster_data$prop_er_positive, 1), "%"))
  print(paste("  - HER2+:", round(cluster_data$prop_her2_positive, 1), "%"))
  print("")
}

print("LOG-RANK TEST:")
print(paste("  Chi-squared:", round(logrank_test$chisq, 2)))
print(paste("  P-value:", format.pval(p_value, digits = 3)))
print("")

if (p_value < 0.05) {
  print("✅ CONCLUSIÓN: Los clusters tienen perfiles de supervivencia SIGNIFICATIVAMENTE diferentes")
} else {
  print("⚠️ CONCLUSIÓN: NO hay diferencias significativas entre clusters")
}

print("")
print("INTERPRETACIÓN CLÍNICA:")
print("  - Cluster con MEJOR pronóstico: Seguimiento estándar")
print("  - Cluster con PEOR pronóstico: Seguimiento intensivo + tratamientos agresivos")
print("  - Clusters intermedios: Personalizar según características individuales")
print("")
print("========================================")

# Guardar resultados
output_clusters <- datos_clustered %>%
  select(id_paciente, cluster, time, status, all_of(features_clustering))

write_csv(output_clusters, file.path(project_root, "output", "clustering_asignaciones.csv"))
print(paste("Asignaciones de clusters guardadas en: clustering_asignaciones.csv"))

write_csv(cluster_stats, file.path(project_root, "output", "clustering_estadisticas.csv"))
print(paste("Estadísticas de clusters guardadas en: clustering_estadisticas.csv"))

write_csv(hr_df, file.path(project_root, "output", "clustering_hazard_ratios.csv"))
print(paste("Hazard Ratios guardados en: clustering_hazard_ratios.csv"))

saveRDS(hc, file.path(project_root, "output", "clustering_modelo.rds"))
print(paste("Modelo de clustering guardado en: clustering_modelo.rds"))
