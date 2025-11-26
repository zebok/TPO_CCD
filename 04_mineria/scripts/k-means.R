# --- SCRIPT FINAL REPARADO ---

library(tidyverse)
library(factoextra)

# 1. CARGAR DATOS
# (Asumimos que el archivo ya cargó bien según tu log anterior)
ruta <- "Desktop/TPO_CCD/02_consolidacion/output/dataset_consolidado_final.csv"
dataset_consolidado_final <- read_csv(ruta)

# 2. PREPARAR DATOS (LA PARTE CRÍTICA)
df_numerico <- dataset_consolidado_final %>%
  select_if(is.numeric) %>%           # Solo números
  select(-any_of("id_paciente"))      # Quitar ID

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
modelo_km <- kmeans(df_final, centers = 5, nstart = 25)

# 5. GRÁFICO
print("Generando gráfico...")
fviz_cluster(modelo_km, data = df_final,
             palette = "jco",
             ggtheme = theme_minimal(),
             geom = "point", # Usamos puntos para que sea más rápido
             main = "K-Means: Distribución de Pacientes")