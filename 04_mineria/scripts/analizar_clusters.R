# --- ANÁLISIS DE CARACTERÍSTICAS DE CLUSTERS ---

library(tidyverse)
library(rprojroot)

# 1. CARGAR DATOS
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
dataset_consolidado_final <- read_csv(dataset_path, show_col_types = FALSE)

# 2. PREPARAR DATOS (mismo proceso que k-means.R)
df_numerico <- dataset_consolidado_final %>%
  dplyr::select(where(is.numeric))

if ("id_paciente" %in% names(df_numerico)) {
  df_numerico <- df_numerico %>% dplyr::select(-id_paciente)
}

df_lleno <- df_numerico %>%
  mutate(across(everything(), ~ifelse(is.na(.), mean(., na.rm = TRUE), .)))

df_final <- scale(df_lleno)

# 3. EJECUTAR K-MEANS (mismo modelo)
set.seed(123)
modelo_km <- kmeans(df_final, centers = 3, nstart = 25)

# 4. AGREGAR CLUSTERS AL DATASET ORIGINAL
df_con_clusters <- df_lleno %>%
  mutate(cluster = modelo_km$cluster)

# 5. ANÁLISIS POR CLUSTER
cat("\n========== RESUMEN DE CLUSTERS ==========\n")
cat("Total de pacientes:", nrow(df_con_clusters), "\n")
cat("Pacientes por cluster:\n")
print(table(df_con_clusters$cluster))

cat("\n========== CENTROIDES (valores promedio por cluster) ==========\n")
# Mostrar las 10 variables más importantes
centroides_df <- as.data.frame(modelo_km$centers)
centroides_df$cluster <- 1:nrow(centroides_df)

# Calcular varianza entre clusters para cada variable
varianza_entre_clusters <- apply(modelo_km$centers, 2, var)
top_vars <- names(sort(varianza_entre_clusters, decreasing = TRUE)[1:10])

cat("\nTop 10 variables que más diferencian los clusters:\n")
print(centroides_df[, c("cluster", top_vars)])

# 6. ESTADÍSTICAS DESCRIPTIVAS POR CLUSTER (en escala original)
cat("\n========== CARACTERÍSTICAS DE CADA CLUSTER (escala original) ==========\n")

for (i in 1:3) {
  cat("\n--- CLUSTER", i, "---\n")
  cat("Tamaño:", sum(df_con_clusters$cluster == i), "pacientes\n")

  cluster_data <- df_con_clusters %>% filter(cluster == i)

  # Mostrar estadísticas de las variables más importantes
  cat("\nPromedios de variables clave:\n")
  for (var in top_vars) {
    if (var %in% names(cluster_data)) {
      valor <- mean(cluster_data[[var]], na.rm = TRUE)
      cat(sprintf("  %s: %.2f\n", var, valor))
    }
  }
}

# 7. GUARDAR RESULTADOS
output_file <- file.path(project_root, "output", "caracteristicas_clusters.txt")
sink(output_file)
cat("========== ANÁLISIS DE CLUSTERS K-MEANS ==========\n\n")
cat("Total de pacientes:", nrow(df_con_clusters), "\n")
cat("Pacientes por cluster:\n")
print(table(df_con_clusters$cluster))
cat("\n\nTop variables discriminantes:\n")
print(centroides_df[, c("cluster", top_vars)])
sink()

cat("\n\nResultados guardados en:", output_file, "\n")
