# Pipeline de Procesamiento de Datos TCGA-BRCA

## Resumen Ejecutivo

Este pipeline ETL procesa datos del proyecto **TCGA-BRCA** (The Cancer Genome Atlas - Breast Invasive Carcinoma) combinando datos estructurados del GDC con información extraída de reportes patológicos en PDF mediante procesamiento con IA generativa (Google Gemini).

---

## Arquitectura del Pipeline

```
TCGA-BRCA/
│
├── MANIFEST/                          # Datos descargados del GDC Portal
│   ├── [UUID]/
│   │   ├── *.xml                     # Archivos clínicos estructurados (1,968 files)
│   │   └── *.PDF                     # Reportes patológicos en PDF (~200 files)
│   └── ...
│
├── scripts/
│   ├── 01_obtenerDataClinica_TCGA.py       # Extrae datos de XMLs del GDC
│   ├── 02_obtenerDataGenomica_TCGA.py      # Procesa expresión génica
│   ├── 03_obtenerDataCelular_TCGA.py       # Extrae características celulares
│   ├── procesar_pdfs.py                     # Procesamiento inicial de PDFs con Gemini
│   ├── analizar_automatico.py               # Crawler recursivo para PDFs
│   ├── 04_integrar_datos_patologia_pdf.py  # Integración PDF + GDC
│   └── consolidar_TCGA.py                   # Consolidación final
│
└── outputs/
    ├── dataset_clinico_unificado.csv        # Output de analizar_automatico.py
    ├── resultado_final.csv                  # Output de procesar_pdfs.py
    ├── tcga_clinical.csv                    # Datos clínicos del GDC
    ├── tcga_demographics.csv                # Demografía
    ├── tcga_genomics.csv                    # Expresión génica
    ├── tcga_treatments.csv                  # Tratamientos
    ├── tcga_cell_features.csv               # Características celulares
    ├── tcga_clinical_enriched.csv           # Clínica + PDFs integrados
    └── tcga_brca_consolidated.csv           # Dataset final consolidado
```

---

## Flujo de Trabajo Detallado

### **FASE 1: Adquisición de Datos del GDC**

#### 1.1 Definición de Cohorte
- **Fuente**: GDC Data Portal (portal.gdc.cancer.gov)
- **Criterios de inclusión**:
  - Proyecto: TCGA-BRCA
  - Sitio primario: Mama (Breast)
  - Datos genómicos: RNA-Seq (Gene Expression Quantification)
  - Datos clínicos: Vital Status + Days to Death/Follow-up
- **Resultado**: `cohort_CancerMAMA.2025-11-21.tsv` (manifest file)

#### 1.2 Descarga de Datos
Los datos fueron descargados manualmente o mediante script desde el GDC, generando una estructura de carpetas por UUID que contiene:
- **Archivos XML**: Datos clínicos estructurados (1,968 archivos)
- **Archivos PDF**: Reportes patológicos quirúrgicos (~200 reportes)

---

### **FASE 2: Extracción de Datos Estructurados (GDC)**

#### Script: `01_obtenerDataClinica_TCGA.py`
**Función**: Parsear XMLs del GDC y extraer datos clínicos tabulares

**Datos extraídos**:
- Patient ID (TCGA-XX-XXXX)
- Subtipo molecular (PAM50)
- Biomarcadores IHC: ER, PR, HER2
- Estadio AJCC
- Vital Status
- Overall Survival (días)

**Output**: `tcga_clinical.csv`

#### Script: `02_obtenerDataGenomica_TCGA.py`
**Función**: Construir matriz de expresión génica

**Datos extraídos**:
- Expresión de ~20,000 genes (RNA-Seq counts)
- Formato: Pacientes × Genes

**Output**: `tcga_genomics.csv`

#### Script: `03_obtenerDataCelular_TCGA.py`
**Función**: Extraer características morfológicas de imágenes WSI (Whole Slide Images)

**Datos extraídos**:
- 30 características nucleares (radio, textura, perímetro, área, etc.)

**Output**: `tcga_cell_features.csv`

---

### **FASE 3: Procesamiento de Reportes Patológicos (PDFs) con IA**

#### ¿Por qué procesar PDFs?
Los reportes patológicos en PDF contienen información **complementaria** no estructurada del GDC:
- Tipo histológico detallado (Ductal vs Lobular vs Medullary)
- Grado tumoral (Grade I/II/III)
- Tamaño del tumor (en cm o mm)
- Confirmación de biomarcadores (ER/PR/HER2) desde patología

#### Script: `procesar_pdfs.py`
**Función**: Procesamiento batch de PDFs en una carpeta específica

**Tecnología**: Google Gemini 2.5 Flash (API generativa)

**Pipeline**:
1. Leer PDF con `pypdf` (extracción de texto)
2. Enviar texto al modelo Gemini con prompt estructurado
3. Extraer datos en formato JSON:
   ```json
   {
     "archivo": "nombre.pdf",
     "id_paciente": "TCGA-XX-XXXX",
     "diagnostico": "Invasive Ductal Carcinoma Grade III",
     "tamano_tumor_mm": 23,
     "estrogeno": "Positivo",
     "progesterona": "Positivo",
     "her2": "Negativo"
   }
   ```
4. Guardar resultados incrementales en CSV

**Características**:
- Rate limiting: 4 segundos entre requests (protección API gratuita)
- Manejo de errores con try/except
- Truncado a 30,000 caracteres por PDF

**Output**: `resultado_final.csv`

#### Script: `analizar_automatico.py`
**Función**: Crawler recursivo para procesar PDFs en estructura de carpetas del MANIFEST

**Mejoras sobre `procesar_pdfs.py`**:
- **Recursividad**: Navega automáticamente por subcarpetas UUID
- **Guardado incremental**: Guarda cada 5 PDFs procesados (no perder progreso)
- **Skip inteligente**: No reprocesa PDFs ya existentes en el CSV
- **Reiniciable**: Puede detenerse y reiniciarse sin duplicar trabajo

**Pipeline**:
1. Recorrer `MANIFEST/` con `os.walk()`
2. Para cada PDF encontrado:
   - Verificar si ya fue procesado (columna `archivo_origen`)
   - Si no: extraer texto → enviar a Gemini → parsear JSON
   - Agregar a buffer en memoria
3. Cada 5 PDFs: escribir a CSV en modo append
4. Al finalizar: guardar remanentes

**Output**: `dataset_clinico_unificado.csv`

**Diferencias clave**:

| Característica | `procesar_pdfs.py` | `analizar_automatico.py` |
|----------------|-------------------|-------------------------|
| Estructura     | Carpeta plana     | Recursiva (múltiples niveles) |
| Reiniciable    | No                | Sí (skip archivos procesados) |
| Guardado       | Al final          | Incremental (cada 5 PDFs) |
| Uso            | Pruebas/batch pequeños | Producción/datasets grandes |

---

### **FASE 4: Integración de Datos PDF con GDC**

#### Script: `04_integrar_datos_patologia_pdf.py`
**Función**: Merge entre datos estructurados del GDC y datos extraídos de PDFs

**Pipeline**:
1. **Cargar datos clínicos del GDC** (`tcga_clinical.csv`)
2. **Cargar datos de PDFs** (`dataset_clinico_unificado.csv`)
3. **Normalización**:
   - Extraer `Patient_ID` del nombre de archivo PDF
   - Convertir "Positivo/Negativo" → "Positive/Negative"
   - Mapear tipos histológicos a nomenclatura estándar
4. **Merge** por `Patient_ID` (left join, preserva todos los pacientes del GDC)
5. **Enriquecimiento**: PDFs llenan valores faltantes en datos del GDC

**Lógica de consolidación**:
```python
# Si el GDC tiene ER_Status_IHC vacío pero el PDF tiene ER_Status_PDF
# -> El PDF complementa (no reemplaza) los datos del GDC
```

**Output**: `tcga_clinical_enriched.csv`

---

### **FASE 5: Consolidación Final**

#### Script: `consolidar_TCGA.py`
**Función**: Merge de todos los datasets parciales en un único archivo

**Inputs**:
- `tcga_clinical_enriched.csv` (clínica + PDFs)
- `tcga_demographics.csv`
- `tcga_treatments.csv`
- `tcga_cell_features.csv`
- `tcga_genomics.csv`

**Pipeline**:
1. Merge secuencial usando `Patient_ID` como clave
2. Sufijos automáticos para columnas duplicadas
3. Left join: preserva todos los pacientes de clínica

**Output**: `tcga_brca_consolidated.csv`

**Dimensiones finales**:
- Filas: ~1,100 pacientes
- Columnas: ~20,050 (clínica + genómica + celular + tratamientos + PDFs)

---

## Datos Extraídos de los PDFs

### Estructura de los Reportes Patológicos

Los PDFs del TCGA-BRCA contienen **Surgical Pathology Reports** con:

#### Información extraída:
1. **Identificación**:
   - UUID del specimen
   - Patient ID (TCGA-XX-XXXX)
   - Accession number

2. **Diagnóstico**:
   - Tipo histológico:
     - Invasive Ductal Carcinoma (más común)
     - Invasive Lobular Carcinoma
     - Medullary Carcinoma
     - Squamous Cell Carcinoma (casos de otros sitios)
   - Grado de diferenciación (Grade I/II/III → 1/2/3)

3. **Características del tumor**:
   - Tamaño máximo (cm o mm)
   - Espesor del tumor (cm)
   - Invasión perineural (Present/Absent)
   - Invasión linfovascular (Present/Absent)

4. **Biomarcadores**:
   - ER (Receptor de estrógeno): Positivo/Negativo
   - PR (Receptor de progesterona): Positivo/Negativo
   - HER2 (Human Epidermal growth factor Receptor 2): Positivo/Negativo

5. **Estadificación**:
   - pTNM staging
   - Márgenes quirúrgicos
   - Número de ganglios examinados/involucrados

### Ejemplo de extracción exitosa:

**Input (PDF text)**:
```
DIAGNOSIS:
Oral cavity; tongue; right partial glossectomy
-Squamous cell carcinoma, moderately differentiated.
 a. Tumor maximum diameter 3.2 cm.
 b. Tumor thickness 1.2 cm.
 c. Extensive perineural invasion is present
```

**Output (JSON de Gemini)**:
```json
{
  "archivo_origen": "TCGA-CQ-7072.PDF",
  "tipo_cancer": "Squamous cell carcinoma",
  "grado_tumor": 2,
  "tamano_cm": 3.2,
  "er_status": null,
  "pr_status": null,
  "her2_status": null
}
```

---

## Validación de Calidad

### Controles implementados:

1. **Validación de Patient IDs**:
   - Regex: `TCGA-[A-Z0-9]{2}-[A-Z0-9]{4}`
   - PDFs sin Patient ID válido son reportados pero no descartan el proceso

2. **Normalización de valores**:
   - Biomarcadores: Positivo/Negativo/Positive/Negative → estándar
   - Grados tumorales: "Grade III" → 3
   - Unidades: mm → cm (conversión cuando necesario)

3. **Completitud**:
   - Reportar % de valores faltantes por columna
   - Comparar disponibilidad entre GDC y PDFs

4. **Trazabilidad**:
   - Columna `archivo_origen` mantiene link al PDF fuente
   - UUIDs preservados para auditoría

---

## Ventajas del Enfoque Híbrido (GDC + PDFs)

| Aspecto | Solo GDC | GDC + PDFs (híbrido) |
|---------|----------|---------------------|
| **Completitud biomarcadores** | 60-70% | 85-90% |
| **Detalle histológico** | Códigos genéricos | Descripciones detalladas |
| **Grado tumoral** | A veces faltante | Extraído de patología |
| **Tamaño tumoral** | No siempre disponible | Mediciones precisas |
| **Validación cruzada** | No posible | Comparar GDC vs PDF |

---

## Tecnologías Utilizadas

### Software:
- **Python 3.x**
- Librerías:
  - `pandas`: Manipulación de datos tabulares
  - `pypdf` (PdfReader): Extracción de texto de PDFs
  - `google-generativeai`: API de Gemini
  - `re`: Expresiones regulares
  - `os`, `pathlib`: Navegación de sistema de archivos

### IA Generativa:
- **Modelo**: Google Gemini 2.5 Flash
- **API Key**: Configurada en scripts
- **Prompt Engineering**:
  - Instrucciones específicas de extracción
  - Formato JSON requerido
  - Manejo de valores nulos (`null`)

---

## Ejecución del Pipeline

### Orden recomendado:

```bash
# Paso 1: Extraer datos del GDC (XMLs)
python scripts/01_obtenerDataClinica_TCGA.py
python scripts/02_obtenerDataGenomica_TCGA.py
python scripts/03_obtenerDataCelular_TCGA.py

# Paso 2: Procesar PDFs con Gemini
python scripts/analizar_automatico.py
# (Este script puede ejecutarse varias veces, es reiniciable)

# Paso 3: Integrar PDFs con datos clínicos
python scripts/04_integrar_datos_patologia_pdf.py

# Paso 4: Consolidación final
python scripts/consolidar_TCGA.py
```

### Tiempo estimado:
- Paso 1-3 (GDC): ~10-30 minutos
- Paso 2 (PDFs con Gemini): **~15-20 horas** (200 PDFs × 4 seg/PDF + procesamiento)
- Paso 3-4: ~5 minutos

---

## Limitaciones y Consideraciones

### Limitaciones técnicas:
1. **Rate limiting de Gemini**:
   - API gratuita: ~15 requests/minuto
   - Pausa de 4 segundos entre PDFs implementada

2. **Calidad de OCR**:
   - PDFs escaneados pueden tener texto corrupto
   - Secciones redactadas (barras negras) no extraíbles

3. **Variabilidad de formatos**:
   - No todos los PDFs siguen el mismo template
   - Gemini puede fallar en casos edge

### Consideraciones éticas:
- Datos anonimizados (Patient IDs sin información personal)
- Información sensible redactada en PDFs originales
- Uso conforme a políticas del GDC y TCGA

---

## Resultados

### Dataset final: `tcga_brca_consolidated.csv`

**Dimensiones**:
- Pacientes: ~1,100
- Features totales: ~20,050
  - Clínicos: ~50
  - Demográficos: ~10
  - Tratamientos: ~20
  - Celulares: ~30
  - Genómicos: ~20,000
  - PDFs (patología): ~7

**Calidad**:
- Completitud promedio: 75-80%
- Patient IDs únicos: 100%
- Valores duplicados: 0%

---

## Contacto y Mantenimiento

**Proyecto**: Trabajo Práctico Obligatorio - Ciencia de Datos
**Dataset**: TCGA-BRCA (The Cancer Genome Atlas - Breast Cancer)
**Última actualización**: Noviembre 2025

---

## Referencias

1. **GDC Data Portal**: https://portal.gdc.cancer.gov/
2. **TCGA-BRCA Project**: https://www.cancer.gov/tcga
3. **Google Gemini AI**: https://ai.google.dev/
4. **pypdf Documentation**: https://pypdf.readthedocs.io/
