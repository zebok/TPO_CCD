"""
Script para consolidar todos los datasets de TCGA_BRCA en un único archivo.
Combina: clinical, demographics, treatments, cell_features, genomics
"""

import pandas as pd
import os
from pathlib import Path

# Rutas
BASE_DIR = Path(__file__).parent.parent  # Sube a TCGA_BRCA/
INPUT_DIR = BASE_DIR / "outputs"
OUTPUT_DIR = BASE_DIR / "outputs"

# Archivos de entrada
CLINICAL = INPUT_DIR / "tcga_clinical.csv"
DEMOGRAPHICS = INPUT_DIR / "tcga_demographics.csv"
TREATMENTS = INPUT_DIR / "tcga_treatments.csv"
CELL_FEATURES = INPUT_DIR / "tcga_cell_features.csv"
GENOMICS = INPUT_DIR / "tcga_genomics.csv"

# Archivo de salida
OUTPUT_FILE = OUTPUT_DIR / "tcga_brca_consolidated.csv"

def load_data():
    """Carga todos los archivos de TCGA_BRCA"""
    print("Cargando datos de TCGA_BRCA...")

    # Cargar cada archivo (CSV)
    df_clinical = pd.read_csv(CLINICAL)
    print(f"  ✓ Clinical: {df_clinical.shape}")

    df_demographics = pd.read_csv(DEMOGRAPHICS)
    print(f"  ✓ Demographics: {df_demographics.shape}")

    df_treatments = pd.read_csv(TREATMENTS)
    print(f"  ✓ Treatments: {df_treatments.shape}")

    df_cell_features = pd.read_csv(CELL_FEATURES)
    print(f"  ✓ Cell features: {df_cell_features.shape}")

    df_genomics = pd.read_csv(GENOMICS)
    print(f"  ✓ Genomics: {df_genomics.shape}")

    return df_clinical, df_demographics, df_treatments, df_cell_features, df_genomics

def consolidate_tcga(df_clinical, df_demographics, df_treatments, df_cell_features, df_genomics):
    """Consolida todos los dataframes usando Patient_ID como key"""
    print("\nConsolidando datasets...")

    # Merge secuencial usando Patient_ID
    df_consolidated = df_clinical.copy()
    print(f"  Base (clinical): {df_consolidated.shape}")

    # Merge con demographics
    df_consolidated = df_consolidated.merge(
        df_demographics,
        on='Patient_ID',
        how='left',
        suffixes=('', '_demo')
    )
    print(f"  + Demographics: {df_consolidated.shape}")

    # Merge con treatments
    df_consolidated = df_consolidated.merge(
        df_treatments,
        on='Patient_ID',
        how='left',
        suffixes=('', '_treat')
    )
    print(f"  + Treatments: {df_consolidated.shape}")

    # Merge con cell features
    df_consolidated = df_consolidated.merge(
        df_cell_features,
        on='Patient_ID',
        how='left',
        suffixes=('', '_cell')
    )
    print(f"  + Cell features: {df_consolidated.shape}")

    # Merge con genomics (este es el más grande)
    df_consolidated = df_consolidated.merge(
        df_genomics,
        on='Patient_ID',
        how='left',
        suffixes=('', '_genom')
    )
    print(f"  + Genomics: {df_consolidated.shape}")

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
    print(f"  ✓ Pacientes únicos: {df['Patient_ID'].nunique()}")

def generate_summary(df):
    """Genera un resumen del dataset consolidado"""
    print("\n" + "="*60)
    print("RESUMEN DEL DATASET CONSOLIDADO TCGA_BRCA")
    print("="*60)
    print(f"Total de registros: {len(df)}")
    print(f"Total de columnas: {len(df.columns)}")
    print(f"Pacientes únicos: {df['Patient_ID'].nunique()}")
    print(f"\nMissing values por columna (top 10):")
    missing = df.isnull().sum().sort_values(ascending=False).head(10)
    for col, count in missing.items():
        pct = (count / len(df)) * 100
        print(f"  {col}: {count} ({pct:.1f}%)")
    print("\nPrimeras columnas:", list(df.columns[:20]))

def main():
    print("="*60)
    print("CONSOLIDACIÓN DE DATOS TCGA_BRCA")
    print("="*60)

    # Cargar datos
    df_clinical, df_demographics, df_treatments, df_cell_features, df_genomics = load_data()

    # Consolidar
    df_consolidated = consolidate_tcga(df_clinical, df_demographics, df_treatments, df_cell_features, df_genomics)

    # Guardar
    save_consolidated(df_consolidated, OUTPUT_FILE)

    # Resumen
    generate_summary(df_consolidated)

    print("\n✓ Consolidación completada exitosamente!")

if __name__ == "__main__":
    main()
