"""
Script para consolidar todos los datasets de SCAN-B en un único archivo.
Combina: patient_demographics, series_matrix, fpkm_expression, image_analysis_metrics
"""

import pandas as pd
import os
from pathlib import Path

# Rutas
BASE_DIR = Path(__file__).parent.parent  # Sube a SCAN_B/
INPUT_DIR = BASE_DIR / "outputs"
OUTPUT_DIR = BASE_DIR / "outputs"

# Archivos de entrada
DEMOGRAPHICS = INPUT_DIR / "scanb_patient_demographics.csv"
SERIES_MATRIX = INPUT_DIR / "GSE96058_series_matrix.txt"
FPKM_EXPRESSION = INPUT_DIR / "GSE96058_fpkm_expression.csv"
IMAGE_ANALYSIS = INPUT_DIR / "image_analysis_metrics.csv"

# Archivo de salida
OUTPUT_FILE = OUTPUT_DIR / "scanb_consolidated.csv"

def load_data():
    """Carga todos los archivos de SCAN-B"""
    print("Cargando datos de SCAN-B...")

    # Demographics (CSV)
    df_demographics = pd.read_csv(DEMOGRAPHICS)
    print(f"  ✓ Demographics: {df_demographics.shape}")

    # Series matrix (TSV)
    df_series = pd.read_csv(SERIES_MATRIX, sep='\t')
    print(f"  ✓ Series matrix: {df_series.shape}")

    # FPKM expression (CSV)
    df_expression = pd.read_csv(FPKM_EXPRESSION)
    print(f"  ✓ FPKM expression: {df_expression.shape}")

    # Image analysis (CSV)
    df_image = pd.read_csv(IMAGE_ANALYSIS)
    print(f"  ✓ Image analysis: {df_image.shape}")

    return df_demographics, df_series, df_expression, df_image

def normalize_patient_ids(df_demographics, df_series, df_expression, df_image):
    """Normaliza los nombres de columnas de ID para hacer merge"""
    print("\nNormalizando IDs de pacientes...")

    # Demographics usa 'Sample'
    if 'Sample' in df_demographics.columns:
        df_demographics = df_demographics.rename(columns={'Sample': 'PATIENT_ID'})
        print(f"  ✓ Demographics: Sample -> PATIENT_ID")

    # Series matrix usa 'Sample_Geo_Accession'
    if 'Sample_Geo_Accession' in df_series.columns:
        df_series = df_series.rename(columns={'Sample_Geo_Accession': 'PATIENT_ID'})
        print(f"  ✓ Series matrix: Sample_Geo_Accession -> PATIENT_ID")

    # Expression usa 'Gene_Symbol' como primera columna (transponer)
    if 'Gene_Symbol' in df_expression.columns:
        # El archivo tiene genes como filas, necesitamos transponerlo
        df_expression = df_expression.set_index('Gene_Symbol').T
        df_expression = df_expression.reset_index()
        df_expression = df_expression.rename(columns={'index': 'PATIENT_ID'})
        print(f"  ✓ Expression: Transpuesto y renombrado a PATIENT_ID")

    # Image analysis usa 'Patient_ID'
    if 'Patient_ID' in df_image.columns:
        df_image = df_image.rename(columns={'Patient_ID': 'PATIENT_ID'})
        print(f"  ✓ Image analysis: Patient_ID -> PATIENT_ID")

    return df_demographics, df_series, df_expression, df_image

def consolidate_scanb(df_demographics, df_series, df_expression, df_image):
    """Consolida todos los dataframes usando PATIENT_ID como key"""
    print("\nConsolidando datasets...")

    # Merge secuencial usando PATIENT_ID
    df_consolidated = df_series.copy()  # Empezamos con series matrix que tiene data clínica
    print(f"  Base (series matrix): {df_consolidated.shape}")

    # Merge con demographics
    df_consolidated = df_consolidated.merge(
        df_demographics,
        on='PATIENT_ID',
        how='left',
        suffixes=('', '_demo')
    )
    print(f"  + Demographics: {df_consolidated.shape}")

    # Merge con image analysis
    df_consolidated = df_consolidated.merge(
        df_image,
        on='PATIENT_ID',
        how='left',
        suffixes=('', '_img')
    )
    print(f"  + Image analysis: {df_consolidated.shape}")

    # Merge con expression (este será el más grande)
    df_consolidated = df_consolidated.merge(
        df_expression,
        on='PATIENT_ID',
        how='left',
        suffixes=('', '_expr')
    )
    print(f"  + Expression: {df_consolidated.shape}")

    return df_consolidated

def save_consolidated(df, output_file):
    """Guarda el dataset consolidado"""
    print(f"\nGuardando archivo consolidado...")
    df.to_csv(output_file, index=False)

    # Stats finales
    file_size_mb = os.path.getsize(output_file) / (1024 * 1024)
    print(f"  ✓ Archivo guardado: {output_file}")
    print(f"  ✓ Tamaño: {file_size_mb:.2f} MB")
    print(f"  ✓ Shape final: {df.shape}")
    print(f"  ✓ Pacientes únicos: {df['PATIENT_ID'].nunique()}")

def generate_summary(df):
    """Genera un resumen del dataset consolidado"""
    print("\n" + "="*60)
    print("RESUMEN DEL DATASET CONSOLIDADO SCAN-B")
    print("="*60)
    print(f"Total de registros: {len(df)}")
    print(f"Total de columnas: {len(df.columns)}")
    print(f"Pacientes únicos: {df['PATIENT_ID'].nunique()}")
    print(f"\nMissing values por columna (top 10):")
    missing = df.isnull().sum().sort_values(ascending=False).head(10)
    for col, count in missing.items():
        pct = (count / len(df)) * 100
        print(f"  {col}: {count} ({pct:.1f}%)")
    print("\nPrimeras columnas:", list(df.columns[:20]))

def main():
    print("="*60)
    print("CONSOLIDACIÓN DE DATOS SCAN-B")
    print("="*60)

    # Cargar datos
    df_demographics, df_series, df_expression, df_image = load_data()

    # Normalizar IDs
    df_demographics, df_series, df_expression, df_image = normalize_patient_ids(
        df_demographics, df_series, df_expression, df_image
    )

    # Consolidar
    df_consolidated = consolidate_scanb(df_demographics, df_series, df_expression, df_image)

    # Guardar
    save_consolidated(df_consolidated, OUTPUT_FILE)

    # Resumen
    generate_summary(df_consolidated)

    print("\n✓ Consolidación completada exitosamente!")

if __name__ == "__main__":
    main()
