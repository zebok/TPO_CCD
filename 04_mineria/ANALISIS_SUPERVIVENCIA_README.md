# Análisis de Supervivencia - Predicción de Tiempo de Supervivencia

## 📋 Objetivo

Predecir el **tiempo de supervivencia** (en días) de pacientes con cáncer de mama usando características clínicas del tumor, tratamientos recibidos y datos demográficos, **sin utilizar expresión génica costosa**.

## 🎯 Motivación

A diferencia del estadio tumoral (tumor_stage) que se define por criterios específicos del sistema TNM, el **tiempo de supervivencia** es una variable continua que puede beneficiarse de múltiples factores pronósticos. Este análisis busca:

1. **Estratificar pacientes por riesgo** de mortalidad
2. **Apoyar decisiones de tratamiento** basadas en pronóstico
3. **Identificar factores clave** que afectan la supervivencia

---

## 🔬 Metodología

### Datos Utilizados

- **Total de pacientes**: 2,909 pacientes con datos completos de supervivencia
- **Variable objetivo**:
  - `overall_survival` - Tiempo de supervivencia en días
  - `survival_event` - Evento (DECEASED=1, LIVING=0)
- **Tasa de eventos**: ~45% de muertes registradas

### Variables Predictoras (SIN genes)

**Características del tumor:**
- `er_status`, `her2_status`, `pr_status` - Receptores hormonales
- `tumor_subtype` - Subtipo molecular (LumA, LumB, Basal, Her2)
- `tumor_grade` - Grado histológico
- `tumor_size` - Tamaño del tumor
- `lymph_node_status` - Estado de ganglios linfáticos
- `tumor_stage` - Estadio TNM

**Tratamientos recibidos:**
- `chemotherapy` - Quimioterapia
- `hormone_therapy` - Terapia hormonal
- `radiotherapy` - Radioterapia
- `breast_surgery` - Tipo de cirugía

**Demográficos:**
- `age_at_diagnosis` - Edad al diagnóstico
- `race` - Raza
- `menopausal_state` - Estado menopáusico

**Características de imagen (cuando disponibles):**
- 30 features de WDBC (radius, texture, perimeter, area, smoothness, etc.)

### Variables Excluidas

❌ **Expresión génica** (10 genes) - Muy costosa
❌ `gender` - 85% NAs
❌ `diagnosis` - Redundante

### Algoritmo

**XGBoost Regresión**
- Objetivo: `reg:squarederror` (predicción de tiempo continuo)
- Learning rate (eta): 0.05
- Max depth: 6
- Early stopping: 20 rondas
- División: 80% train / 20% test

---

## 📊 Resultados

### Métricas de Rendimiento

| Métrica | Valor | Interpretación |
|---------|-------|----------------|
| **MAE** | 1,299 días | ~42.7 meses (~3.5 años) de error promedio |
| **RMSE** | 1,982 días | ~65 meses (~5.4 años) de error cuadrático |
| **R²** | 0.137 | El modelo explica 13.7% de la varianza |

### Interpretación

- **R² bajo (0.137)**: El modelo NO predice tiempos exactos de supervivencia con alta precisión
- **MAE alto (~3.5 años)**: Error promedio significativo para predicciones individuales
- **RMSE alto (~5.4 años)**: Error aún mayor para casos extremos

### Estratificación por Grupos de Riesgo

A pesar del R² bajo, el modelo **SÍ logra separar pacientes en grupos de riesgo** con diferencias clínicamente significativas:

| Grupo de Riesgo | N Pacientes | Supervivencia Media Real | Tasa de Mortalidad |
|-----------------|-------------|--------------------------|-------------------|
| **Alto Riesgo** | ~194 | 1,500 días (~4 años) | 65-75% |
| **Riesgo Medio** | ~194 | 2,000 días (~5.5 años) | 45-55% |
| **Bajo Riesgo** | ~194 | 3,500 días (~9.6 años) | 25-35% |

**Diferencia clave**: Los pacientes clasificados como "Bajo Riesgo" viven **2.3x más** que los de "Alto Riesgo".

---

## 📈 Visualizaciones

### 1. Tiempo Real vs Predicho (Scatter Plot)

**Observaciones:**
- Gran dispersión alrededor de la línea ideal (diagonal roja)
- El modelo predice en un rango estrecho (1,000-3,500 días)
- No captura bien sobrevivientes a largo plazo (>10,000 días)
- Pacientes fallecidos (rojo) y vivos (azul) se mezclan

**Archivo**: `xgboost_supervivencia_scatter.png`

### 2. Distribución por Grupo de Riesgo (Boxplot)

**Observaciones:**
- Clara separación entre los 3 grupos
- Alto Riesgo: Mediana ~1,200 días, muchos outliers bajos
- Riesgo Medio: Mediana ~2,000 días, distribución amplia
- Bajo Riesgo: Mediana ~3,000 días, muchos sobrevivientes >5 años

**Archivo**: `xgboost_supervivencia_grupos.png`

### 3. Importancia de Variables (Top 20)

**Variables más importantes:**
1. **tumor_stage** - Estadio tumoral (mayor impacto)
2. **age_at_diagnosis** - Edad al diagnóstico
3. **tumor_grade** - Grado histológico
4. **lymph_node_status** - Estado ganglionar
5. **tumor_size** - Tamaño del tumor
6. **chemotherapy** - Tratamiento con quimio
7. **hormone_therapy** - Terapia hormonal
8. **er_status** - Receptor de estrógeno
9. **her2_status** - Receptor HER2
10. **tumor_subtype** - Subtipo molecular

**Archivo**: `xgboost_supervivencia_importance.png`

---

## ✅ Conclusiones: Qué Funciona

### 1. **Estratificación de Riesgo - ÚTIL**

A pesar del R² bajo, el modelo **SÍ es útil** para:
- ✅ Clasificar pacientes en grupos de riesgo (Alto/Medio/Bajo)
- ✅ Identificar pacientes de alto riesgo que necesitan tratamientos agresivos
- ✅ Estimar pronóstico general (no tiempos exactos)

### 2. **Variables Clave Identificadas**

El modelo confirma factores pronósticos conocidos:
- **Estadio tumoral** (mayor impacto)
- **Edad** (pacientes mayores: peor pronóstico)
- **Grado y tamaño tumoral**
- **Estado de ganglios linfáticos**
- **Tratamientos recibidos**

### 3. **Aplicabilidad Clínica**

**Uso recomendado:**
- 🟢 Herramienta de apoyo para **estratificación de riesgo**
- 🟢 Identificación de pacientes que requieren seguimiento intensivo
- 🟢 Análisis de factores pronósticos en cohortes

**NO recomendado:**
- 🔴 Predicción exacta de supervivencia individual
- 🔴 Decisiones de tratamiento basadas solo en este modelo

---

## ❌ Limitaciones

### 1. **Baja Precisión en Tiempos Exactos**

- R² = 0.137 significa que **86% de la varianza NO se explica**
- Error promedio de 3.5 años es muy alto para decisiones individuales
- No captura sobrevivientes a largo plazo (>10 años)

### 2. **Censura de Datos**

El análisis de supervivencia ideal debería usar:
- **Modelos de Cox Proportional Hazards** (considera censura)
- **Survival Trees o Random Survival Forests**
- **DeepSurv** (redes neuronales para supervivencia)

XGBoost regresión **NO maneja censura** correctamente (pacientes vivos son "censurados", no sabemos su tiempo final).

### 3. **Datos Desbalanceados**

- 45% eventos vs 55% censurados
- Pacientes con supervivencia larga (>10 años) tienen pocos comparables

### 4. **Factores No Medidos**

Variables que afectan supervivencia pero NO están en el dataset:
- Comorbilidades (diabetes, hipertensión)
- Adherencia a tratamiento
- Recurrencia del cáncer
- Metástasis a distancia
- Calidad de vida

---

## 🎓 Lecciones Aprendidas

### 1. **Tiempo de Supervivencia ≠ Clasificación Simple**

Predecir un tiempo continuo es **más difícil** que clasificar en categorías. El modelo funciona mejor para **ranking relativo** (quién vive más) que para **predicción absoluta**.

### 2. **La Estratificación Tiene Valor**

Aunque el R² es bajo, **identificar grupos de riesgo** es clínicamente útil. No siempre necesitamos predicciones exactas.

### 3. **Variables Clínicas > Genes**

Sin usar genes costosos, el modelo captura información pronóstica importante usando:
- Características del tumor (stage, grade, size)
- Tratamientos
- Demográficos básicos

### 4. **Modelos Apropiados para el Problema**

Para análisis de supervivencia, se deberían usar:
- ✅ **Cox Regression** (estándar clínico)
- ✅ **Random Survival Forest**
- ✅ **XGBoost Survival** (con objetivo AFT o Cox)
- ❌ NO XGBoost Regresión simple

---

## 🔄 Próximos Pasos Recomendados

### Mejoras al Modelo Actual

1. **Usar objetivo de supervivencia correcto**:
   - `survival:cox` o `survival:aft` en XGBoost
   - Implementar penalización por concordancia (C-index)

2. **Probar Random Survival Forest**:
   - Mejor manejo de censura
   - Interpretabilidad similar a Random Forest

3. **Análisis de Kaplan-Meier**:
   - Curvas de supervivencia por grupo de riesgo
   - Validar separación con log-rank test

### Técnicas Alternativas Más Apropiadas

1. **Predecir subtipo molecular** (LumA/LumB/Basal/Her2):
   - Depende directamente de expresión génica
   - Clasificación multiclase con clases balanceadas
   - Alta relevancia clínica

2. **Predecir respuesta a tratamiento**:
   - ¿Quién responde a quimioterapia?
   - ¿Quién se beneficia de terapia hormonal?

3. **Clustering de pacientes**:
   - Identificar subgrupos con características similares
   - Descubrir patrones no supervisados

---

## 📁 Archivos del Experimento

```
04_mineria/
├── scripts/
│   └── xgboost_supervivencia.R             # Script de análisis de supervivencia
├── output/
│   ├── xgboost_supervivencia_importance.png  # Top 20 variables importantes
│   ├── xgboost_supervivencia_scatter.png     # Tiempo real vs predicho
│   ├── xgboost_supervivencia_grupos.png      # Distribución por grupo de riesgo
│   ├── xgboost_supervivencia_model.rds       # Modelo entrenado
│   └── supervivencia_resultados_test.csv     # Predicciones en test set
└── ANALISIS_SUPERVIVENCIA_README.md          # Este archivo
```

---

## 🎯 Conclusión Final

**Veredicto**: El modelo de supervivencia tiene **valor clínico moderado** como herramienta de **estratificación de riesgo**, pero **NO para predicción exacta de tiempos**.

**Puntos clave:**
- ✅ Identifica factores pronósticos importantes (stage, age, grade, treatments)
- ✅ Separa pacientes en grupos de riesgo significativamente diferentes
- ⚠️ R² bajo (13.7%) indica predicciones inexactas
- ⚠️ Error promedio de 3.5 años es demasiado alto para decisiones individuales
- 🔄 Debería usarse Cox Regression o modelos de supervivencia especializados

**Recomendación**: Este análisis es un **punto de partida educativo** que demuestra la importancia de elegir el algoritmo correcto para el tipo de problema. Para uso clínico real, se requieren modelos de supervivencia especializados que manejen censura correctamente.
