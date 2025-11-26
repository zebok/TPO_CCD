# Experimento: Predicción de Tumor Stage con Datos Accesibles

## 📋 Objetivo del Experimento

Evaluar si es posible **predecir el estadio del cáncer de mama** (tumor_stage) utilizando **únicamente información accesible y económica**, sin recurrir a biomarcadores costosos o procedimientos invasivos.

### Motivación

El objetivo social era determinar si pacientes con recursos limitados podrían obtener un diagnóstico de estadio tumoral usando:

- ✅ Información demográfica (edad, raza, estado menopáusico)
- ✅ Características de imagen médica básica (30 features)
- ✅ Expresión génica (10 genes)

**Sin necesidad de:**

- ❌ Biopsias invasivas que quizas el paciente se niega, por motivos religiosos o imposibles por salud o ubicación.
- ❌ Biomarcadores específicos costosos (ER, HER2, PR status)
- ❌ Estudios de imagen avanzados costosos.

---

## 🔬 Metodología

### Datos Utilizados

- **Total de pacientes**: 6,156
- **Pacientes con tumor_stage conocido**: 922 (15%)
- **Variables predictoras**: 43 features
  - Edad
  - Demográficos (raza, estado menopáusico)
  - 10 genes de expresión (esr1, pgr, erbb2, mki67, tp53, brca1, brca2, pik3ca, pten, akt1)
  - 30 características de imagen (radius, texture, perimeter, area, smoothness, etc.)

### Variables Excluidas (por ser consecuencia del stage o costosas)

- `er_status`, `her2_status`, `pr_status` (biomarcadores)
- `tumor_grade`, `tumor_size`, `lymph_node_status` (características tumorales)
- `chemotherapy`, `hormone_therapy`, `radiotherapy`, `breast_surgery` (tratamientos)
- `survival_event`, `overall_survival`, `vital_status` (outcomes)

### Algoritmo

**XGBoost** (Extreme Gradient Boosting)

- Clasificación multiclase y binaria
- Balanceo de clases mediante pesos
- Early stopping y validación cruzada

---

## 📊 Experimentos Realizados

### Experimento 1: Clasificación Multiclase (4 categorías)

**Objetivo**: Predecir Stage I, II, III, IV

**Distribución de clases**:

- Stage I: 191 casos (21%)
- Stage II: 391 casos (42%)
- Stage III: 243 casos (26%)
- Stage IV: 97 casos (11%)

**Resultados**:
| Clase | Precision | Recall | F1-Score |
|-------|-----------|--------|----------|
| Stage I | 17.8% | 21.0% | 19.3% |
| Stage II | 43.3% | 50.0% | 46.4% |
| Stage III | 18.9% | 14.6% | 16.5% |
| Stage IV | 9.1% | 5.3% | 6.7% |

**Accuracy global**: 38.8%

**Archivos generados**:

- Script: `xgboost_tumor_stage_4clases.R`
- Gráficos: `xgboost_tumor_stage_4clases_confusion.png`, `xgboost_tumor_stage_4clases_importance.png`
- Modelo: `xgboost_tumor_stage_4clases_model.rds`

---

### Experimento 2: Clasificación Binaria (Early vs Advanced)

**Objetivo**: Simplificar a 2 categorías

- **Early**: Stage I + II (tumores menos agresivos)
- **Advanced**: Stage III + IV (tumores más agresivos)

**Distribución**:

- Early: 582 casos (63%)
- Advanced: 340 casos (37%)

**Resultados**:

```
Accuracy: 52.72%

Métricas:
- Sensitivity (Recall): 38.24%
- Specificity: 61.21%
- Precision: 36.62%
- F1-Score: 37.41%

Matriz de Confusión:
              Real
Predicho    Advanced  Early
Advanced        26      45
Early           42      71
```

**Problema crítico**: De 71 casos predichos como "Early", 42 son en realidad "Advanced" (59% de error en la clase más peligrosa)

**Archivos generados**:

- Script: `xgboost_tumor_stage.R`
- Gráficos: `xgboost_tumor_stage_binary_confusion.png`, `xgboost_tumor_stage_importance.png`
- Modelo: `xgboost_tumor_stage_binary_model.rds`

---

## ❌ Conclusiones: Por Qué NO Funciona

### 1. **Limitación Fundamental**

El **tumor_stage** se define clínicamente mediante el sistema TNM:

- **T (Tumor)**: Tamaño exacto del tumor primario
- **N (Nodes)**: Número de ganglios linfáticos afectados
- **M (Metastasis)**: Presencia de metástasis a distancia

Estas características:

- ✅ **SÍ requieren**: Biopsia, estudios de imagen avanzados, análisis patológico
- ❌ **NO se pueden inferir de**: Expresión génica o características de imagen básica

### 2. **Datos Insuficientes**

- Solo 922 pacientes con stage conocido (15% del dataset)
- Clases muy desbalanceadas (Stage IV: 97 casos vs Stage II: 391 casos)
- 55% de NAs en variables de expresión génica

### 3. **Variables Predictoras Inadecuadas**

Las variables disponibles (genes, imagen) **no tienen relación causal directa** con el estadio:

- La expresión génica determina el **subtipo molecular** (LumA, Basal, etc.), NO el stage
- Las características de imagen básica no sustituyen la evaluación histopatológica

### 4. **Riesgo Clínico Inaceptable**

Un modelo con **38% de Sensitivity** para detectar casos avanzados es **clínicamente peligroso**:

- 62% de tumores avanzados serían clasificados incorrectamente como "Early"
- Esto retrasaría tratamientos agresivos necesarios
- Pondría vidas en riesgo

---

## ✅ Qué Se Necesitaría para Mejorar

### Para predecir tumor_stage correctamente, se requiere:

1. **Datos clínicos directos**:

   - Tamaño tumoral exacto (cm)
   - Estado de ganglios linfáticos (número afectados)
   - Presencia de metástasis
   - Grado histológico

2. **Estudios diagnósticos**:

   - Biopsia con análisis patológico
   - Mamografía/ecografía de alta resolución
   - PET-CT para detección de metástasis
   - Biopsia de ganglio centinela

3. **Más datos**:
   - Dataset más grande (>5,000 pacientes con stage conocido)
   - Menos valores faltantes
   - Variables balanceadas

---

## 📚 Lecciones Aprendidas

### 1. **No todo es predecible con ML**

Algunos problemas médicos requieren información específica que no puede ser inferida de variables proxy.

### 2. **El contexto clínico importa**

El tumor_stage existe porque médicos necesitan información precisa (TNM) para decidir tratamientos. No es una clasificación "natural" emergente de los datos.

### 3. **Los fracasos son valiosos**

Este experimento demuestra científicamente **por qué** el estadio tumoral requiere estudios diagnósticos específicos. Refuerza la importancia de:

- Acceso a salud de calidad
- Protocolos de diagnóstico estandarizados
- No sustituir juicio clínico con algoritmos inadecuados

### 4. **Mejores aplicaciones de ML en oncología**:

- ✅ Predecir **subtipo molecular** (más relacionado con genes)
- ✅ Estimar **tiempo de supervivencia** (análisis de supervivencia)
- ✅ Identificar **patrones de respuesta a tratamiento**
- ✅ Detectar **recurrencia temprana**

**Conclusión Final**: Este experimento demuestra empíricamente que **predecir tumor_stage con datos accesibles no es médicamente viable ni ético**. El estadiamiento requiere información clínica específica obtenida mediante protocolos diagnósticos establecidos. El Machine Learning debe complementar, no sustituir, la práctica clínica basada en evidencia.
