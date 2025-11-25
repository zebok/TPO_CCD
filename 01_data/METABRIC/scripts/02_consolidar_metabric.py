"""
Script para consolidar todos los datasets de METABRIC en un único archivo.
Combina: clinical_patient, clinical_sample, nuclei_morphology y mRNA expression
"""

import pandas as pd
import os
from pathlib import Path

# Rutas
BASE_DIR = Path(__file__).parent.parent  # Sube a METABRIC/
INPUT_DIR = BASE_DIR / "outputs"
OUTPUT_DIR = BASE_DIR / "outputs"

# Archivos de entrada
CLINICAL_PATIENT = INPUT_DIR / "data_clinical_patient.txt"
CLINICAL_SAMPLE = INPUT_DIR / "data_clinical_sample.txt"
NUCLEI_MORPHOLOGY = INPUT_DIR / "nuclei_morphology.txt"
MRNA_EXPRESSION = INPUT_DIR / "data_mRNA_median_Zscores.txt"

# Archivo de salida
OUTPUT_FILE = OUTPUT_DIR / "metabric_consolidated.csv"

def load_data():
    """Carga todos los archivos de METABRIC"""
    print("Cargando datos de METABRIC...")

    # Cargar cada archivo (tab-separated)
    df_patient = pd.read_csv(CLINICAL_PATIENT, sep='\t')
    print(f"  ✓ Clinical patient: {df_patient.shape}")

    df_sample = pd.read_csv(CLINICAL_SAMPLE, sep='\t')
    print(f"  ✓ Clinical sample: {df_sample.shape}")

    df_nuclei = pd.read_csv(NUCLEI_MORPHOLOGY, sep='\t')
    print(f"  ✓ Nuclei morphology: {df_nuclei.shape}")

    df_mrna = pd.read_csv(MRNA_EXPRESSION, sep='\t')
    print(f"  ✓ mRNA expression: {df_mrna.shape}")

    return df_patient, df_sample, df_nuclei, df_mrna

def consolidate_metabric(df_patient, df_sample, df_nuclei, df_mrna):
    """Consolida todos los dataframes usando PATIENT_ID como key"""
    print("\nConsolidando datasets...")

    # Merge secuencial usando PATIENT_ID
    df_consolidated = df_patient.copy()
    print(f"  Base: {df_consolidated.shape}")

    # Merge con clinical sample
    df_consolidated = df_consolidated.merge(
        df_sample,
        on='PATIENT_ID',
        how='left'
    )
    print(f"  + Clinical sample: {df_consolidated.shape}")

    # Merge con nuclei morphology
    df_consolidated = df_consolidated.merge(
        df_nuclei,
        on='PATIENT_ID',
        how='left'
    )
    print(f"  + Nuclei morphology: {df_consolidated.shape}")

    # Merge con mRNA expression
    df_consolidated = df_consolidated.merge(
        df_mrna,
        on='PATIENT_ID',
        how='left'
    )
    print(f"  + mRNA expression: {df_consolidated.shape}")

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
    print("RESUMEN DEL DATASET CONSOLIDADO METABRIC")
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
    print("CONSOLIDACIÓN DE DATOS METABRIC")
    print("="*60)

    # Cargar datos
    df_patient, df_sample, df_nuclei, df_mrna = load_data()

    # Consolidar
    df_consolidated = consolidate_metabric(df_patient, df_sample, df_nuclei, df_mrna)

    # Guardar
    save_consolidated(df_consolidated, OUTPUT_FILE)

    # Resumen
    generate_summary(df_consolidated)

    print("\n✓ Consolidación completada exitosamente!")

if __name__ == "__main__":
    main()
