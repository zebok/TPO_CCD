# Script para calcular el % de completitud de las columnas de genes
# ========================================================================

library(dplyr)
library(tidyr)

# 1) Cargar datos ---------------------------------------------------------
# Ruta al dataset consolidado
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
bd <- read.csv(dataset_path, header = TRUE, stringsAsFactors = FALSE)

cat("Dataset cargado correctamente.\n")
cat("Dimensiones:", nrow(bd), "filas x", ncol(bd), "columnas\n\n")

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

# Verificar que todas las columnas existen en el dataset
genes_existentes <- genes_cols[genes_cols %in% names(bd)]
genes_faltantes <- genes_cols[!genes_cols %in% names(bd)]

if (length(genes_faltantes) > 0) {
  cat("⚠️  ADVERTENCIA: Las siguientes columnas de genes NO se encontraron en el dataset:\n")
  cat(paste("  -", genes_faltantes, collapse = "\n"), "\n\n")
}

# 3) Calcular completitud -------------------------------------------------
completitud <- data.frame(
  gen = genes_existentes,
  total_filas = nrow(bd),
  valores_presentes = NA,
  valores_faltantes = NA,
  pct_completitud = NA,
  pct_faltante = NA
)

for (i in seq_along(genes_existentes)) {
  gen <- genes_existentes[i]
  
  # Contar valores no-NA
  presentes <- sum(!is.na(bd[[gen]]))
  faltantes <- sum(is.na(bd[[gen]]))
  
  completitud$valores_presentes[i] <- presentes
  completitud$valores_faltantes[i] <- faltantes
  completitud$pct_completitud[i] <- round((presentes / nrow(bd)) * 100, 2)
  completitud$pct_faltante[i] <- round((faltantes / nrow(bd)) * 100, 2)
}

# 4) Ordenar por completitud (descendente) --------------------------------
completitud <- completitud %>%
  arrange(desc(pct_completitud))

# 5) Mostrar resultados ---------------------------------------------------
cat(strrep("=", 70), "\n")
cat("REPORTE DE COMPLETITUD DE GENES\n")
cat(strrep("=", 70), "\n\n")

print(completitud, row.names = FALSE)

cat("\n")
cat(strrep("=", 70), "\n")
cat("RESUMEN ESTADÍSTICO\n")
cat(strrep("=", 70), "\n")
cat("Completitud promedio:", round(mean(completitud$pct_completitud), 2), "%\n")
cat("Completitud mínima:  ", round(min(completitud$pct_completitud), 2), "%\n")
cat("Completitud máxima:  ", round(max(completitud$pct_completitud), 2), "%\n")
cat("Mediana:             ", round(median(completitud$pct_completitud), 2), "%\n")

# 6) Visualización --------------------------------------------------------
library(ggplot2)

# Gráfico de barras de completitud
p <- ggplot(completitud, aes(x = reorder(gen, pct_completitud), y = pct_completitud)) +
  geom_col(aes(fill = pct_completitud), width = 0.7) +
  geom_text(aes(label = paste0(pct_completitud, "%")), 
            hjust = -0.1, size = 3.5, fontface = "bold") +
  scale_fill_gradient(low = "#FC4E07", high = "#00AFBB", 
                      name = "% Completitud") +
  coord_flip() +
  ylim(0, 105) +
  labs(
    title = "Completitud de Datos de Expresión Génica",
    subtitle = paste0("Dataset: ", nrow(bd), " pacientes"),
    x = "Gen",
    y = "% de Valores Presentes"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0),
    plot.subtitle = element_text(size = 11, color = "grey40", hjust = 0),
    axis.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "none"
  )

print(p)

# 7) Guardar resultados ---------------------------------------------------
# Crear carpeta output si no existe
output_dir <- file.path(project_root, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Guardar tabla
write.csv(completitud, 
          file.path(output_dir, "completitud_genes.csv"), 
          row.names = FALSE)

# Guardar gráfico
ggsave(
  filename = file.path(output_dir, "completitud_genes.png"),
  plot = p,
  width = 10,
  height = 6,
  dpi = 300,
  bg = "white"
)

cat("\n✅ Resultados guardados en:\n")
cat("   - Tabla:", file.path(output_dir, "completitud_genes.csv"), "\n")
cat("   - Gráfico:", file.path(output_dir, "completitud_genes.png"), "\n")
