"""
Script para consolidar los 3 datasets (METABRIC, SCAN-B, TCGA_BRCA)
usando el mapeo manual de columnas definido en column_mapping_manual.yaml
"""

import pandas as pd
import yaml
from pathlib import Path
import numpy as np

# Rutas
BASE_DIR = Path(__file__).parent.parent.parent  # Sube a TPO_CCD/
METABRIC_FILE = BASE_DIR / "01_data" / "METABRIC" / "outputs" / "metabric_consolidated.csv"
SCANB_FILE = BASE_DIR / "01_data" / "SCAN_B" / "outputs" / "scanb_consolidated.csv"
TCGA_FILE = BASE_DIR / "01_data" / "TCGA_BRCA" / "outputs" / "tcga_brca_consolidated.csv"

SCRIPT_DIR = Path(__file__).parent  # 02_consolidacion/scripts/
MAPPING_FILE = SCRIPT_DIR / "column_mapping_manual.yaml"
OUTPUT_DIR = SCRIPT_DIR.parent / "output"  # 02_consolidacion/output/
OUTPUT_FILE = OUTPUT_DIR / "dataset_consolidado_final.csv"

def load_column_mapping():
    """Carga el mapeo manual de columnas desde el YAML"""
    print("Cargando mapeo de columnas...")
    with open(MAPPING_FILE, 'r') as f:
        mapping = yaml.safe_load(f)

    # Filtrar comentarios y metadatos
    mapping = {k: v for k, v in mapping.items() if isinstance(v, dict) and 'tipo' in v}

    print(f"  ✓ {len(mapping)} columnas mapeadas")
    return mapping

def load_datasets():
    """Carga los 3 datasets consolidados"""
    print("\nCargando datasets consolidados...")

    df_metabric = pd.read_csv(METABRIC_FILE)
    print(f"  ✓ METABRIC: {df_metabric.shape}")

    df_scanb = pd.read_csv(SCANB_FILE)
    print(f"  ✓ SCAN-B: {df_scanb.shape}")

    df_tcga = pd.read_csv(TCGA_FILE)
    print(f"  ✓ TCGA_BRCA: {df_tcga.shape}")

    return df_metabric, df_scanb, df_tcga

def apply_mapping_to_dataset(df, dataset_name, mapping):
    """
    Aplica el mapeo de columnas a un dataset específico.
    Renombra las columnas según el mapeo y mantiene solo las columnas mapeadas.
    """
    print(f"\nAplicando mapeo a {dataset_name}...")

    # Crear diccionario de renombrado: columna_original -> columna_unificada
    rename_dict = {}
    for unified_name, sources in mapping.items():
        source_col = sources.get(dataset_name.lower())
        if source_col and source_col != 'null' and source_col in df.columns:
            rename_dict[source_col] = unified_name

    # Renombrar columnas
    df_mapped = df[list(rename_dict.keys())].copy()
    df_mapped = df_mapped.rename(columns=rename_dict)

    # Agregar columna de origen
    df_mapped['dataset_source'] = dataset_name

    print(f"  ✓ Columnas mapeadas: {len(rename_dict)}")
    print(f"  ✓ Shape después de mapeo: {df_mapped.shape}")

    return df_mapped

def normalize_values(df):
    """
    Normaliza valores para que sean compatibles entre datasets.
    Por ejemplo: convertir meses a días, estandarizar valores categóricos, etc.
    """
    print("\nNormalizando valores...")

    # Convertir overall_survival a días si existe
    if 'overall_survival' in df.columns:
        # METABRIC: convertir meses a días (1 mes = 30.44 días)
        mask_metabric = df['dataset_source'] == 'METABRIC'
        if mask_metabric.any():
            df.loc[mask_metabric, 'overall_survival'] = df.loc[mask_metabric, 'overall_survival'] * 30.44
            print("  ✓ Convertido OS_MONTHS a días (METABRIC)")

        # SCANB: convertir años a días (1 año = 365.25 días)
        mask_scanb = df['dataset_source'] == 'SCANB'
        if mask_scanb.any():
            df.loc[mask_scanb, 'overall_survival'] = df.loc[mask_scanb, 'overall_survival'] * 365.25
            print("  ✓ Convertido FollowUp_Years a días (SCAN-B)")

        # TCGA ya está en días, no necesita conversión

    # Normalizar valores de ER status (Pos/Positive/1 -> Positive, Neg/Negative/0 -> Negative)
    if 'er_status' in df.columns:
        df['er_status'] = df['er_status'].replace({
            'Pos': 'Positive',
            'pos': 'Positive',
            '1': 'Positive',
            1: 'Positive',
            'Neg': 'Negative',
            'neg': 'Negative',
            '0': 'Negative',
            0: 'Negative',
            'NEUTRAL': 'Neutral'
        })

    # Normalizar valores de tratamientos (YES/1/True -> Yes, NO/0/False -> No)
    treatment_cols = ['chemotherapy', 'hormone_therapy', 'radiotherapy']
    for col in treatment_cols:
        if col in df.columns:
            df[col] = df[col].replace({
                'YES': 'Yes',
                'yes': 'Yes',
                1: 'Yes',
                1.0: 'Yes',
                True: 'Yes',
                'NO': 'No',
                'no': 'No',
                0: 'No',
                0.0: 'No',
                False: 'No'
            })

    print("  ✓ Valores normalizados")
    return df

def consolidate_all_datasets(df_metabric, df_scanb, df_tcga, mapping):
    """Consolida los 3 datasets usando el mapeo"""
    print("\n" + "="*80)
    print("CONSOLIDANDO DATASETS")
    print("="*80)

    # Aplicar mapeo a cada dataset
    df_metabric_mapped = apply_mapping_to_dataset(df_metabric, 'METABRIC', mapping)
    df_scanb_mapped = apply_mapping_to_dataset(df_scanb, 'SCANB', mapping)
    df_tcga_mapped = apply_mapping_to_dataset(df_tcga, 'TCGA', mapping)

    # Concatenar verticalmente (union de filas)
    print("\nConcatenando datasets...")
    df_consolidated = pd.concat([df_metabric_mapped, df_scanb_mapped, df_tcga_mapped],
                                ignore_index=True,
                                sort=False)

    print(f"  ✓ Shape consolidado: {df_consolidated.shape}")
    print(f"  ✓ Registros por dataset:")
    print(df_consolidated['dataset_source'].value_counts())

    # Normalizar valores
    df_consolidated = normalize_values(df_consolidated)

    return df_consolidated

def generate_summary(df):
    """Genera un resumen del dataset consolidado final"""
    print("\n" + "="*80)
    print("RESUMEN DEL DATASET CONSOLIDADO FINAL")
    print("="*80)

    print(f"\nTotal de registros: {len(df)}")
    print(f"Total de columnas: {len(df.columns)}")

    print(f"\nRegistros por dataset:")
    print(df['dataset_source'].value_counts())

    print(f"\nPacientes únicos totales: {df['id_paciente'].nunique()}")

    print(f"\nColumnas disponibles:")
    for col in sorted(df.columns):
        non_null = df[col].notna().sum()
        pct = (non_null / len(df)) * 100
        print(f"  {col}: {non_null}/{len(df)} ({pct:.1f}% completo)")

    print(f"\nMissing values por columna (top 10 con más missing):")
    missing = df.isnull().sum().sort_values(ascending=False).head(10)
    for col, count in missing.items():
        pct = (count / len(df)) * 100
        print(f"  {col}: {count} ({pct:.1f}%)")

def save_consolidated(df, output_file):
    """Guarda el dataset consolidado"""
    print(f"\nGuardando dataset consolidado...")
    df.to_csv(output_file, index=False)

    # Stats finales
    import os
    file_size_mb = os.path.getsize(output_file) / (1024 * 1024)
    print(f"  ✓ Archivo guardado: {output_file}")
    print(f"  ✓ Tamaño: {file_size_mb:.2f} MB")

def main():
    print("="*80)
    print("CONSOLIDACIÓN FINAL DE TODOS LOS DATASETS")
    print("="*80)

    # Cargar mapeo
    mapping = load_column_mapping()

    # Cargar datasets
    df_metabric, df_scanb, df_tcga = load_datasets()

    # Consolidar
    df_consolidated = consolidate_all_datasets(df_metabric, df_scanb, df_tcga, mapping)

    # Guardar
    save_consolidated(df_consolidated, OUTPUT_FILE)

    # Resumen
    generate_summary(df_consolidated)

    print("\n" + "="*80)
    print("✓ CONSOLIDACIÓN COMPLETADA EXITOSAMENTE!")
    print("="*80)
    print(f"\nArchivo final: {OUTPUT_FILE}")
    print(f"Para modificar el mapeo de columnas, edita: {MAPPING_FILE}")

if __name__ == "__main__":
    main()
