# --- SCRIPT FINAL REPARADO ---

library(tidyverse)
library(factoextra)
library(rprojroot)

# 1. CARGAR DATOS
# Ruta relativa desde el proyecto RStudio (04_mineria.Rproj)
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
dataset_consolidado_final <- read_csv(dataset_path)

# 2. PREPARAR DATOS (LA PARTE CRÍTICA)
df_numerico <- dataset_consolidado_final %>%
  dplyr::select(where(is.numeric))    # Solo números

# Quitar ID si existe
if ("id_paciente" %in% names(df_numerico)) {
  df_numerico <- df_numerico %>% dplyr::select(-id_paciente)
}

# --- AQUÍ ESTÁ EL CAMBIO MÁGICO ---
# En vez de borrar (na.omit), rellenamos los NAs con la media de cada columna.
# Si falta un dato, asumimos que es "promedio".
df_lleno <- df_numerico %>%
  mutate(across(everything(), ~ifelse(is.na(.), mean(., na.rm = TRUE), .)))

# 3. ESCALAR
df_final <- scale(df_lleno)
print(paste("¡Salvados! Ahora tienes", nrow(df_final), "pacientes listos para analizar."))

# 4. EJECUTAR K-MEANS
set.seed(123)
modelo_km <- kmeans(df_final, centers = 3, nstart = 25)

# 5. GRÁFICO
print("Generando gráfico...")
plot_kmeans <- fviz_cluster(modelo_km, data = df_final,
                            palette = "jco",
                            ggtheme = theme_minimal(),
                            geom = "point", # Usamos puntos para que sea más rápido
                            main = "K-Means: Distribución de Pacientes")

# Mostrar el gráfico
print(plot_kmeans)

# Guardar en output
output_path <- file.path(project_root, "output", "kmeans_cluster.png")
ggsave(output_path, plot = plot_kmeans, width = 10, height = 8, dpi = 300)
print(paste("Gráfico guardado en:", output_path))