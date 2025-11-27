# ANÁLISIS DE DISPARIDADES POR RAZA/ETNIA EN CÁNCER DE MAMA
# ========================================================================
# Pregunta: ¿Hay diferencias en estadio al diagnóstico o supervivencia según raza?
# Hipótesis: Existen disparidades en el acceso o detección temprana.
# ========================================================================

library(dplyr)
library(ggplot2)
library(tidyr)
library(survival)
library(survminer)

# 1) CARGAR DATOS ---------------------------------------------------------
project_root <- rprojroot::find_root(rprojroot::has_file("04_mineria.Rproj"))
dataset_path <- file.path(dirname(project_root), "02_consolidacion", "output", "dataset_consolidado_final.csv")
bd <- read.csv(dataset_path, header = TRUE, stringsAsFactors = FALSE)

cat("Dataset cargado correctamente.\n")
cat("Total de pacientes:", nrow(bd), "\n\n")

# 2) PREPARAR DATOS -------------------------------------------------------

# Convertir variables categóricas a factor
bd <- bd %>%
  mutate(
    race = factor(race),
    tumor_stage = factor(tumor_stage, 
                        levels = c("Stage I", "Stage II", "Stage III", "Stage IV"),
                        ordered = TRUE),
    vital_status = factor(vital_status),
    tumor_grade = factor(tumor_grade),
    tumor_subtype = factor(tumor_subtype)
  )

# Crear variable de supervivencia binaria
bd <- bd %>%
  mutate(
    fallecido = ifelse(vital_status == "Dead", 1, 0),
    vivo = ifelse(vital_status == "Alive", 1, 0)
  )

# Filtrar solo pacientes con información de raza
bd_race <- bd %>%
  filter(!is.na(race) & race != "" & race != "not reported")

cat("Pacientes con información de raza:", nrow(bd_race), "\n")
cat("Razas/etnias en el dataset:\n")
print(table(bd_race$race))
cat("\n")

# 3) ANÁLISIS 1: ESTADIO AL DIAGNÓSTICO POR RAZA -------------------------

cat(strrep("=", 80), "\n")
cat("ANÁLISIS 1: ESTADIO AL DIAGNÓSTICO POR RAZA\n")
cat(strrep("=", 80), "\n\n")

# Tabla cruzada: raza × estadio
tabla_raza_estadio <- bd_race %>%
  filter(!is.na(tumor_stage)) %>%
  group_by(race, tumor_stage) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(race) %>%
  mutate(
    total_raza = sum(n),
    pct = round((n / total_raza) * 100, 2)
  ) %>%
  ungroup()

print(tabla_raza_estadio)

# Tabla pivoteada para mejor visualización
tabla_pivot <- tabla_raza_estadio %>%
  select(race, tumor_stage, pct) %>%
  pivot_wider(names_from = tumor_stage, values_from = pct, values_fill = 0)

cat("\n% de pacientes por estadio según raza:\n")
print(tabla_pivot, n = Inf)

# Filtrar solo las razas principales para el análisis estadístico
razas_principales <- bd_race %>%
  count(race) %>%
  filter(n >= 50) %>%
  pull(race)

bd_race_filtrado <- bd_race %>%
  filter(race %in% razas_principales)

cat("\nRazas incluidas en el análisis estadístico (n ≥ 50):\n")
print(table(bd_race_filtrado$race))

# Test Chi-cuadrado para independencia
cat("\n--- Test Chi-cuadrado: Raza × Estadio ---\n")
tabla_contingencia <- table(bd_race_filtrado$race, bd_race_filtrado$tumor_stage)
print(tabla_contingencia)

# Intentar test Chi-cuadrado con manejo de errores
test_chi <- tryCatch({
  chisq.test(tabla_contingencia)
}, warning = function(w) {
  cat("\n⚠️  Advertencia:", w$message, "\n")
  chisq.test(tabla_contingencia, simulate.p.value = TRUE)
}, error = function(e) {
  cat("\n❌ Error en test Chi-cuadrado:", e$message, "\n")
  list(p.value = NA, statistic = NA)
})

print(test_chi)

if (!is.na(test_chi$p.value)) {
  if (test_chi$p.value < 0.05) {
    cat("\n✅ RESULTADO: Hay asociación significativa entre raza y estadio (p < 0.05)\n")
  } else {
    cat("\n❌ RESULTADO: No hay asociación significativa entre raza y estadio (p ≥ 0.05)\n")
  }
} else {
  cat("\n⚠️  No se pudo calcular el test Chi-cuadrado (datos insuficientes)\n")
}

# Calcular % de diagnósticos en estadios avanzados (III-IV) por raza
cat("\n--- % de Diagnósticos en Estadios Avanzados (Stage III-IV) ---\n")
estadios_avanzados <- bd_race %>%
  filter(!is.na(tumor_stage)) %>%
  mutate(
    estadio_avanzado = ifelse(tumor_stage %in% c("Stage III", "Stage IV"), 1, 0)
  ) %>%
  group_by(race) %>%
  summarise(
    total = n(),
    n_avanzado = sum(estadio_avanzado),
    pct_avanzado = round((n_avanzado / total) * 100, 2)
  ) %>%
  arrange(desc(pct_avanzado))

print(estadios_avanzados)

# 4) ANÁLISIS 2: SUPERVIVENCIA POR RAZA ----------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("ANÁLISIS 2: SUPERVIVENCIA POR RAZA\n")
cat(strrep("=", 80), "\n\n")

# Tabla de supervivencia por raza
tabla_supervivencia <- bd_race %>%
  filter(!is.na(vital_status)) %>%
  group_by(race, vital_status) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(race) %>%
  mutate(
    total = sum(n),
    pct = round((n / total) * 100, 2)
  )

print(tabla_supervivencia)

# % de fallecidos por raza
cat("\n--- % de Pacientes Fallecidos por Raza ---\n")
pct_fallecidos <- bd_race %>%
  filter(!is.na(vital_status)) %>%
  group_by(race) %>%
  summarise(
    total = n(),
    fallecidos = sum(vital_status == "Dead"),
    pct_fallecidos = round((fallecidos / total) * 100, 2)
  ) %>%
  arrange(desc(pct_fallecidos))

print(pct_fallecidos)

# Test Chi-cuadrado: Raza × Vital Status
cat("\n--- Test Chi-cuadrado: Raza × Vital Status ---\n")
tabla_vital <- table(bd_race_filtrado$race, bd_race_filtrado$vital_status)
print(tabla_vital)

test_vital <- tryCatch({
  chisq.test(tabla_vital)
}, warning = function(w) {
  cat("\n⚠️  Advertencia:", w$message, "\n")
  chisq.test(tabla_vital, simulate.p.value = TRUE)
}, error = function(e) {
  cat("\n❌ Error en test Chi-cuadrado:", e$message, "\n")
  list(p.value = NA, statistic = NA)
})

print(test_vital)

if (!is.na(test_vital$p.value)) {
  if (test_vital$p.value < 0.05) {
    cat("\n✅ RESULTADO: Hay asociación significativa entre raza y supervivencia (p < 0.05)\n")
  } else {
    cat("\n❌ RESULTADO: No hay asociación significativa entre raza y supervivencia (p ≥ 0.05)\n")
  }
} else {
  cat("\n⚠️  No se pudo calcular el test Chi-cuadrado (datos insuficientes)\n")
}

# 5) ANÁLISIS DE SUPERVIVENCIA (KAPLAN-MEIER) ----------------------------

# Solo si tenemos datos de tiempo de supervivencia
if ("days_to_death" %in% names(bd_race) || "days_to_last_follow_up" %in% names(bd_race)) {
  
  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("ANÁLISIS 3: CURVAS DE SUPERVIVENCIA (KAPLAN-MEIER)\n")
  cat(strrep("=", 80), "\n\n")
  
  # Crear variable de tiempo y evento
  bd_surv <- bd_race %>%
    mutate(
      time = ifelse(!is.na(days_to_death), days_to_death, days_to_last_follow_up),
      time = ifelse(is.na(time) | time <= 0, NA, time),
      event = ifelse(vital_status == "Dead", 1, 0)
    ) %>%
    filter(!is.na(time) & !is.na(race))
  
  if (nrow(bd_surv) > 0) {
    # Ajustar modelo de supervivencia
    surv_obj <- Surv(time = bd_surv$time, event = bd_surv$event)
    fit_surv <- survfit(surv_obj ~ race, data = bd_surv)
    
    # Log-rank test
    cat("--- Log-rank Test: Comparación de Curvas de Supervivencia ---\n")
    logrank_test <- survdiff(surv_obj ~ race, data = bd_surv)
    print(logrank_test)
    
    if (logrank_test$pvalue < 0.05) {
      cat("\n✅ RESULTADO: Hay diferencias significativas en supervivencia entre razas (p < 0.05)\n")
    } else {
      cat("\n❌ RESULTADO: No hay diferencias significativas en supervivencia entre razas (p ≥ 0.05)\n")
    }
    
    # Medianas de supervivencia
    cat("\n--- Medianas de Supervivencia por Raza (días) ---\n")
    print(summary(fit_surv)$table)
  }
}

# 6) VISUALIZACIONES ------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("GENERANDO VISUALIZACIONES...\n")
cat(strrep("=", 80), "\n\n")

# Paleta de colores vibrante (ampliada para cubrir todas las categorías)
colores_raza <- c("#E63946", "#F1C453", "#06A77D", "#457B9D", "#A8DADC", "#F4A261", 
                  "#E76F51", "#2A9D8F", "#264653", "#E9C46A")

# GRÁFICO 1: Distribución de estadios por raza
p1 <- bd_race %>%
  filter(!is.na(tumor_stage)) %>%
  ggplot(aes(x = race, fill = tumor_stage)) +
  geom_bar(position = "fill", width = 0.7) +
  geom_text(aes(label = after_stat(count)), 
            stat = "count", 
            position = position_fill(vjust = 0.5),
            size = 3, fontface = "bold", color = "white") +
  scale_fill_manual(values = c("#00AFBB", "#E7B800", "#FC4E07", "#8B0000"),
                    name = "Estadio Tumoral") +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title = "Distribución de Estadios Tumorales por Raza/Etnia",
    subtitle = "Proporción de pacientes en cada estadio al diagnóstico",
    x = "Raza/Etnia",
    y = "Proporción de Pacientes"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0),
    plot.subtitle = element_text(size = 11, color = "grey40", hjust = 0),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "right",
    panel.grid.major.x = element_blank()
  )

print(p1)

# GRÁFICO 2: % de estadios avanzados por raza
p2 <- estadios_avanzados %>%
  ggplot(aes(x = reorder(race, pct_avanzado), y = pct_avanzado, fill = race)) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = paste0(pct_avanzado, "%")), 
            hjust = -0.2, size = 4, fontface = "bold") +
  scale_fill_manual(values = colores_raza) +
  coord_flip() +
  ylim(0, max(estadios_avanzados$pct_avanzado) * 1.15) +
  labs(
    title = "Porcentaje de Diagnósticos en Estadios Avanzados (III-IV)",
    subtitle = "Indicador de detección tardía por raza/etnia",
    x = "Raza/Etnia",
    y = "% de Pacientes en Estadios III-IV"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0),
    plot.subtitle = element_text(size = 11, color = "grey40", hjust = 0),
    axis.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank()
  )

print(p2)

# GRÁFICO 3: Tasa de mortalidad por raza
p3 <- pct_fallecidos %>%
  ggplot(aes(x = reorder(race, pct_fallecidos), y = pct_fallecidos, fill = race)) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = paste0(pct_fallecidos, "%\n(", fallecidos, "/", total, ")")), 
            hjust = -0.1, size = 3.5, fontface = "bold") +
  scale_fill_manual(values = colores_raza) +
  coord_flip() +
  ylim(0, max(pct_fallecidos$pct_fallecidos) * 1.2) +
  labs(
    title = "Tasa de Mortalidad por Raza/Etnia",
    subtitle = "Porcentaje de pacientes fallecidos según raza",
    x = "Raza/Etnia",
    y = "% de Pacientes Fallecidos"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0),
    plot.subtitle = element_text(size = 11, color = "grey40", hjust = 0),
    axis.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank()
  )

print(p3)

# GRÁFICO 4: Curvas de supervivencia (si hay datos)
if (exists("bd_surv") && nrow(bd_surv) > 0) {
  p4 <- ggsurvplot(
    fit_surv,
    data = bd_surv,
    pval = TRUE,
    conf.int = TRUE,
    risk.table = TRUE,
    risk.table.height = 0.3,
    palette = colores_raza,
    ggtheme = theme_minimal(base_size = 12),
    title = "Curvas de Supervivencia de Kaplan-Meier por Raza/Etnia",
    xlab = "Tiempo (días)",
    ylab = "Probabilidad de Supervivencia",
    legend.title = "Raza/Etnia",
    legend.labs = levels(bd_surv$race)
  )
  
  print(p4)
}

# 7) GUARDAR RESULTADOS ---------------------------------------------------

output_dir <- file.path(project_root, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Guardar tablas
write.csv(tabla_raza_estadio, 
          file.path(output_dir, "disparidades_raza_estadio.csv"), 
          row.names = FALSE)

write.csv(estadios_avanzados, 
          file.path(output_dir, "disparidades_raza_estadios_avanzados.csv"), 
          row.names = FALSE)

write.csv(pct_fallecidos, 
          file.path(output_dir, "disparidades_raza_mortalidad.csv"), 
          row.names = FALSE)

# Guardar gráficos
ggsave(file.path(output_dir, "disparidades_estadios_por_raza.png"),
       plot = p1, width = 10, height = 6, dpi = 300, bg = "white")

ggsave(file.path(output_dir, "disparidades_estadios_avanzados.png"),
       plot = p2, width = 10, height = 6, dpi = 300, bg = "white")

ggsave(file.path(output_dir, "disparidades_mortalidad.png"),
       plot = p3, width = 10, height = 6, dpi = 300, bg = "white")

if (exists("p4")) {
  ggsave(file.path(output_dir, "disparidades_curvas_supervivencia.png"),
         plot = print(p4), width = 12, height = 8, dpi = 300, bg = "white")
}

# Crear reporte resumen
reporte <- c(
  "========================================================================",
  "REPORTE: DISPARIDADES POR RAZA/ETNIA EN CÁNCER DE MAMA",
  "========================================================================",
  "",
  paste("Fecha de análisis:", Sys.Date()),
  paste("Total de pacientes analizados:", nrow(bd_race)),
  "",
  "--- HALLAZGOS PRINCIPALES ---",
  "",
  "1. ESTADIO AL DIAGNÓSTICO:",
  paste("   - Test Chi-cuadrado p-value:", ifelse(!is.na(test_chi$p.value), round(test_chi$p.value, 4), "NA")),
  ifelse(!is.na(test_chi$p.value) && test_chi$p.value < 0.05, 
         "   - Conclusión: HAY asociación significativa entre raza y estadio",
         ifelse(!is.na(test_chi$p.value),
                "   - Conclusión: NO hay asociación significativa entre raza y estadio",
                "   - Conclusión: No se pudo calcular (datos insuficientes)")),
  "",
  "2. SUPERVIVENCIA:",
  paste("   - Test Chi-cuadrado p-value:", ifelse(!is.na(test_vital$p.value), round(test_vital$p.value, 4), "NA")),
  ifelse(!is.na(test_vital$p.value) && test_vital$p.value < 0.05,
         "   - Conclusión: HAY asociación significativa entre raza y supervivencia",
         ifelse(!is.na(test_vital$p.value),
                "   - Conclusión: NO hay asociación significativa entre raza y supervivencia",
                "   - Conclusión: No se pudo calcular (datos insuficientes)")),
  "",
  "--- ARCHIVOS GENERADOS ---",
  "Tablas:",
  "  - disparidades_raza_estadio.csv",
  "  - disparidades_raza_estadios_avanzados.csv",
  "  - disparidades_raza_mortalidad.csv",
  "",
  "Gráficos:",
  "  - disparidades_estadios_por_raza.png",
  "  - disparidades_estadios_avanzados.png",
  "  - disparidades_mortalidad.png",
  ifelse(exists("p4"), "  - disparidades_curvas_supervivencia.png", ""),
  "========================================================================"
)

writeLines(reporte, file.path(output_dir, "REPORTE_DISPARIDADES_RAZA.txt"))

cat("\n")
cat(strrep("=", 80), "\n")
cat("✅ ANÁLISIS COMPLETADO\n")
cat(strrep("=", 80), "\n")
cat("Todos los resultados se guardaron en:\n")
cat(output_dir, "\n\n")
cat("Archivos generados:\n")
cat("  📊 3 tablas CSV\n")
cat("  📈 3-4 gráficos PNG\n")
cat("  📄 1 reporte resumen TXT\n")
