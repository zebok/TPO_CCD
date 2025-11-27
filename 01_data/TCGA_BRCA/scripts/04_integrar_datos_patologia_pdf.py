"""
Script 04: Integración de Datos de Patología desde PDFs procesados con Gemini
================================================================================
Este script toma los datos extraídos de reportes patológicos en PDF
(procesados previamente con analizar_automatico.py) y los integra con
los datos clínicos estructurados del GDC.

Autor: Pipeline TCGA-BRCA
Fecha: Noviembre 2025
"""

import pandas as pd
import re
from pathlib import Path

# Configuración de rutas
BASE_DIR = Path(__file__).parent.parent
OUTPUTS_DIR = BASE_DIR / "outputs"

# Archivos de entrada
CLINICAL_FILE = OUTPUTS_DIR / "tcga_clinical.csv"
PDF_EXTRACTED_FILE = OUTPUTS_DIR / "dataset_clinico_unificado.csv"

# Archivo de salida
OUTPUT_FILE = OUTPUTS_DIR / "tcga_clinical_enriched.csv"

def extraer_patient_id_de_pdf(nombre_archivo_pdf):
    """
    Extrae el Patient_ID del nombre del archivo PDF.
    Ejemplo: 'TCGA-A2-AJI0_pathology_report.pdf' -> 'TCGA-A2-AJI0'
    """
    match = re.match(r'(TCGA-[A-Z0-9]{2}-[A-Z0-9]{4})', nombre_archivo_pdf)
    if match:
        return match.group(1)
    return None

def normalizar_biomarcadores(valor):
    """
    Normaliza los valores de biomarcadores de español a inglés.
    Positivo/Negativo -> Positive/Negative
    """
    if pd.isna(valor):
        return valor

    valor_lower = str(valor).lower()
    if 'positiv' in valor_lower:
        return 'Positive'
    elif 'negativ' in valor_lower:
        return 'Negative'
    return valor

def mapear_tipo_cancer(tipo_pdf):
    """
    Mapea el tipo de cáncer del PDF a códigos histológicos estándar.
    """
    if pd.isna(tipo_pdf):
        return None

    tipo_lower = str(tipo_pdf).lower()

    if 'ductal' in tipo_lower:
        return 'Invasive Ductal Carcinoma'
    elif 'lobular' in tipo_lower:
        return 'Invasive Lobular Carcinoma'
    elif 'medullary' in tipo_lower:
        return 'Medullary Carcinoma'

    return tipo_pdf

def integrar_datos_patologia():
    """
    Función principal que integra datos de PDFs con datos clínicos del GDC.
    """
    print("="*70)
    print("INTEGRACIÓN DE DATOS DE PATOLOGÍA (PDFs procesados con Gemini)")
    print("="*70)

    # 1. Cargar datos clínicos del GDC
    print("\n[1/4] Cargando datos clínicos del GDC...")
    df_clinical = pd.read_csv(CLINICAL_FILE)
    print(f"  ✓ Cargados {len(df_clinical)} pacientes del GDC")

    # 2. Cargar datos extraídos de PDFs
    print("\n[2/4] Cargando datos extraídos de reportes patológicos (PDFs)...")
    df_pdfs = pd.read_csv(PDF_EXTRACTED_FILE)
    print(f"  ✓ Cargados {len(df_pdfs)} reportes patológicos procesados")

    # 3. Preparar datos de PDFs para merge
    print("\n[3/4] Procesando y mapeando datos de PDFs...")

    # Extraer Patient_ID del nombre de archivo
    df_pdfs['Patient_ID'] = df_pdfs['archivo_origen'].apply(extraer_patient_id_de_pdf)

    # Normalizar biomarcadores (Positivo/Negativo -> Positive/Negative)
    df_pdfs['er_status'] = df_pdfs['er_status'].apply(normalizar_biomarcadores)
    df_pdfs['pr_status'] = df_pdfs['pr_status'].apply(normalizar_biomarcadores)
    df_pdfs['her2_status'] = df_pdfs['her2_status'].apply(normalizar_biomarcadores)

    # Mapear tipo de cáncer
    df_pdfs['tipo_cancer'] = df_pdfs['tipo_cancer'].apply(mapear_tipo_cancer)

    # Renombrar columnas para indicar que provienen de PDFs
    df_pdfs_clean = df_pdfs[['Patient_ID', 'tipo_cancer', 'grado_tumor',
                              'tamano_cm', 'er_status', 'pr_status', 'her2_status']].copy()

    df_pdfs_clean.columns = ['Patient_ID', 'Histologic_Type_PDF', 'Tumor_Grade_PDF',
                             'Tumor_Size_cm_PDF', 'ER_Status_PDF', 'PR_Status_PDF', 'HER2_Status_PDF']

    print(f"  ✓ Procesados {df_pdfs_clean['Patient_ID'].notna().sum()} Patient_IDs válidos")

    # 4. Merge con datos clínicos
    print("\n[4/4] Integrando datos de PDFs con datos clínicos del GDC...")
    df_enriched = df_clinical.merge(
        df_pdfs_clean,
        on='Patient_ID',
        how='left',
        suffixes=('', '_PDF')
    )

    # Consolidar información: usar PDFs para llenar valores faltantes
    # Si ER_Status_IHC está vacío pero ER_Status_PDF tiene valor, usarlo
    for marker in ['ER', 'PR', 'HER2']:
        ihc_col = f'{marker}_Status_IHC'
        pdf_col = f'{marker}_Status_PDF'

        if ihc_col in df_enriched.columns and pdf_col in df_enriched.columns:
            # Contar cuántos valores se llenarán
            missing_count = df_enriched[ihc_col].isna().sum()
            pdf_available = df_enriched[pdf_col].notna().sum()

            print(f"  • {marker}: {missing_count} valores faltantes en GDC, {pdf_available} disponibles en PDFs")

    # 5. Guardar dataset enriquecido
    print(f"\n[5/5] Guardando dataset enriquecido...")
    df_enriched.to_csv(OUTPUT_FILE, index=False)

    print(f"  ✓ Archivo guardado: {OUTPUT_FILE}")
    print(f"  ✓ Shape final: {df_enriched.shape}")

    # 6. Resumen de integración
    print("\n" + "="*70)
    print("RESUMEN DE INTEGRACIÓN")
    print("="*70)
    print(f"Total de pacientes en dataset final: {len(df_enriched)}")
    print(f"Pacientes con datos de PDFs integrados: {df_enriched['ER_Status_PDF'].notna().sum()}")
    print(f"Pacientes solo con datos GDC: {df_enriched['ER_Status_PDF'].isna().sum()}")

    # Estadísticas de completitud
    print("\nCompletitud de biomarcadores:")
    for marker in ['ER', 'PR', 'HER2']:
        ihc_col = f'{marker}_Status_IHC'
        pdf_col = f'{marker}_Status_PDF'

        if ihc_col in df_enriched.columns:
            gdc_complete = df_enriched[ihc_col].notna().sum()
            print(f"  {marker} (GDC):  {gdc_complete}/{len(df_enriched)} ({100*gdc_complete/len(df_enriched):.1f}%)")

        if pdf_col in df_enriched.columns:
            pdf_complete = df_enriched[pdf_col].notna().sum()
            print(f"  {marker} (PDFs): {pdf_complete}/{len(df_enriched)} ({100*pdf_complete/len(df_enriched):.1f}%)")

    print("\n✓ Integración completada exitosamente!")
    return df_enriched

if __name__ == "__main__":
    df_final = integrar_datos_patologia()
