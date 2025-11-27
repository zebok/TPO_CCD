# Script para identificar pacientes con datos completos de los 10 genes
# ========================================================================

library(dplyr)

# 1) Cargar datos ---------------------------------------------------------
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
bd <- read.csv(dataset_path, header = TRUE, stringsAsFactors = FALSE)

cat("Dataset cargado correctamente.\n")
cat("Total de pacientes en el dataset:", nrow(bd), "\n\n")

# 2) Definir columnas de genes --------------------------------------------
genes_cols <- c(
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

# 3) Contar NAs por paciente ----------------------------------------------
# Crear una columna que cuente cuántos genes faltan por cada paciente
bd$genes_faltantes <- apply(bd[, genes_cols], 1, function(x) sum(is.na(x)))

# 4) Análisis de completitud ----------------------------------------------
cat(strrep("=", 70), "\n")
cat("ANÁLISIS DE COMPLETITUD DE GENES POR PACIENTE\n")
cat(strrep("=", 70), "\n\n")

# Tabla de frecuencias: cuántos pacientes tienen X genes faltantes
tabla_completitud <- table(bd$genes_faltantes)
df_completitud <- data.frame(
  genes_faltantes = as.numeric(names(tabla_completitud)),
  n_pacientes = as.numeric(tabla_completitud)
)
df_completitud$pct_pacientes <- round((df_completitud$n_pacientes / nrow(bd)) * 100, 2)
df_completitud$genes_presentes <- 10 - df_completitud$genes_faltantes

# Reordenar columnas
df_completitud <- df_completitud[, c("genes_presentes", "genes_faltantes", "n_pacientes", "pct_pacientes")]

print(df_completitud, row.names = FALSE)

# 5) Pacientes con TODOS los genes completos -----------------------------
pacientes_completos <- bd %>%
  filter(genes_faltantes == 0)

cat("\n")
cat(strrep("=", 70), "\n")
cat("PACIENTES CON LOS 10 GENES COMPLETOS\n")
cat(strrep("=", 70), "\n")
cat("Total de pacientes con los 10 genes:", nrow(pacientes_completos), "\n")
cat("Porcentaje del dataset total:", 
    round((nrow(pacientes_completos) / nrow(bd)) * 100, 2), "%\n\n")

# 6) Estadísticas adicionales ---------------------------------------------
cat(strrep("=", 70), "\n")
cat("ESTADÍSTICAS ADICIONALES\n")
cat(strrep("=", 70), "\n")

# Pacientes con al menos 1 gen
pacientes_con_algun_gen <- sum(bd$genes_faltantes < 10)
cat("Pacientes con al menos 1 gen:", pacientes_con_algun_gen, 
    "(", round((pacientes_con_algun_gen / nrow(bd)) * 100, 2), "%)\n")

# Pacientes sin ningún gen
pacientes_sin_genes <- sum(bd$genes_faltantes == 10)
cat("Pacientes sin ningún gen:     ", pacientes_sin_genes,
    "(", round((pacientes_sin_genes / nrow(bd)) * 100, 2), "%)\n")

# Pacientes con al menos 5 genes
pacientes_5_o_mas <- sum(bd$genes_faltantes <= 5)
cat("Pacientes con ≥5 genes:       ", pacientes_5_o_mas,
    "(", round((pacientes_5_o_mas / nrow(bd)) * 100, 2), "%)\n")

# Promedio de genes por paciente
promedio_genes <- mean(10 - bd$genes_faltantes)
cat("\nPromedio de genes por paciente:", round(promedio_genes, 2), "\n")

# 7) Visualización --------------------------------------------------------
library(ggplot2)

# Gráfico de barras
p1 <- ggplot(df_completitud, aes(x = genes_presentes, y = n_pacientes)) +
  geom_col(aes(fill = genes_presentes), width = 0.7) +
  geom_text(aes(label = paste0(n_pacientes, "\n(", pct_pacientes, "%)")), 
            vjust = -0.3, size = 3, fontface = "bold") +
  scale_fill_gradient(low = "#FC4E07", high = "#00AFBB", 
                      name = "Genes\nPresentes") +
  scale_x_continuous(breaks = 0:10) +
  labs(
    title = "Distribución de Pacientes por Número de Genes Presentes",
    subtitle = paste0("Dataset: ", nrow(bd), " pacientes totales"),
    x = "Número de Genes Presentes (de 10)",
    y = "Número de Pacientes"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0),
    plot.subtitle = element_text(size = 11, color = "grey40", hjust = 0),
    axis.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    legend.position = "right"
  )

print(p1)

# 8) Guardar resultados ---------------------------------------------------
output_dir <- file.path(project_root, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Guardar tabla de completitud
write.csv(df_completitud, 
          file.path(output_dir, "distribucion_genes_por_paciente.csv"), 
          row.names = FALSE)

# Guardar lista de IDs de pacientes con todos los genes
write.csv(pacientes_completos %>% select(id_paciente), 
          file.path(output_dir, "pacientes_10_genes_completos.csv"), 
          row.names = FALSE)

# Guardar dataset filtrado con solo pacientes completos
write.csv(pacientes_completos, 
          file.path(output_dir, "dataset_pacientes_genes_completos.csv"), 
          row.names = FALSE)

# Guardar gráfico
ggsave(
  filename = file.path(output_dir, "distribucion_genes_pacientes.png"),
  plot = p1,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

cat("\n")
cat(strrep("=", 70), "\n")
cat("✅ RESULTADOS GUARDADOS\n")
cat(strrep("=", 70), "\n")
cat("📊 Tabla de distribución:\n")
cat("   ", file.path(output_dir, "distribucion_genes_por_paciente.csv"), "\n\n")
cat("👥 Lista de IDs de pacientes con 10 genes:\n")
cat("   ", file.path(output_dir, "pacientes_10_genes_completos.csv"), "\n\n")
cat("💾 Dataset filtrado (solo pacientes con 10 genes):\n")
cat("   ", file.path(output_dir, "dataset_pacientes_genes_completos.csv"), "\n\n")
cat("📈 Gráfico:\n")
cat("   ", file.path(output_dir, "distribucion_genes_pacientes.png"), "\n")
