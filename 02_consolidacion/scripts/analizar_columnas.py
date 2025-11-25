"""
Script para analizar las columnas de los 3 datasets consolidados
y encontrar qué columnas matchean entre ellos.
"""

import pandas as pd
from pathlib import Path
from collections import defaultdict
import re

# Rutas
BASE_DIR = Path(__file__).parent.parent.parent  # Sube a TPO_CCD/
METABRIC_FILE = BASE_DIR / "01_data" / "METABRIC" / "outputs" / "metabric_consolidated.csv"
SCANB_FILE = BASE_DIR / "01_data" / "SCAN_B" / "outputs" / "scanb_consolidated.csv"
TCGA_FILE = BASE_DIR / "01_data" / "TCGA_BRCA" / "outputs" / "tcga_brca_consolidated.csv"

OUTPUT_DIR = Path(__file__).parent.parent / "output"  # 02_consolidacion/output/
MAPPING_FILE = OUTPUT_DIR / "column_mapping.txt"

def normalize_column_name(col):
    """Normaliza nombres de columnas para comparación"""
    # Convertir a minúsculas y remover caracteres especiales
    normalized = col.lower()
    normalized = re.sub(r'[_\s.-]+', '_', normalized)
    normalized = normalized.strip('_')
    return normalized

def categorize_columns(columns):
    """Categoriza columnas por tipo de dato"""
    categories = {
        'clinical': [],
        'demographic': [],
        'treatment': [],
        'genomic': [],
        'imaging': [],
        'survival': [],
        'identifier': [],
        'other': []
    }

    for col in columns:
        col_lower = col.lower()

        if 'patient' in col_lower or 'sample' in col_lower or col_lower in ['patient_id', 'sample_id']:
            categories['identifier'].append(col)
        elif any(x in col_lower for x in ['er_', 'pr_', 'her2', 'erbb2', 'subtype', 'grade', 'stage', 'ihc']):
            categories['clinical'].append(col)
        elif any(x in col_lower for x in ['age', 'race', 'gender', 'ethnicity', 'nationality', 'smoking']):
            categories['demographic'].append(col)
        elif any(x in col_lower for x in ['treatment', 'therapy', 'chemo', 'radiation', 'hormone']):
            categories['treatment'].append(col)
        elif any(x in col_lower for x in ['esr1', 'pgr', 'tp53', 'brca', 'pik3ca', 'pten', 'mki67', 'gene_', 'fpkm']):
            categories['genomic'].append(col)
        elif any(x in col_lower for x in ['nuc_', 'radius', 'texture', 'perimeter', 'area', 'smoothness', 'compactness', 'concavity', 'symmetry', 'fractal', 'morphology', 'cell_']):
            categories['imaging'].append(col)
        elif any(x in col_lower for x in ['survival', 'vital', 'death', 'followup', 'os_', 'event']):
            categories['survival'].append(col)
        else:
            categories['other'].append(col)

    return categories

def find_similar_columns(metabric_cols, scanb_cols, tcga_cols):
    """Encuentra columnas similares entre datasets"""

    # Normalizar todas las columnas
    metabric_normalized = {normalize_column_name(col): col for col in metabric_cols}
    scanb_normalized = {normalize_column_name(col): col for col in scanb_cols}
    tcga_normalized = {normalize_column_name(col): col for col in tcga_cols}

    # Encontrar matches exactos (después de normalizar)
    all_normalized = set(metabric_normalized.keys()) | set(scanb_normalized.keys()) | set(tcga_normalized.keys())

    matches = defaultdict(lambda: {'metabric': [], 'scanb': [], 'tcga': []})

    for norm_col in all_normalized:
        if norm_col in metabric_normalized:
            matches[norm_col]['metabric'].append(metabric_normalized[norm_col])
        if norm_col in scanb_normalized:
            matches[norm_col]['scanb'].append(scanb_normalized[norm_col])
        if norm_col in tcga_normalized:
            matches[norm_col]['tcga'].append(tcga_normalized[norm_col])

    return matches

def analyze_datasets():
    """Analiza los 3 datasets consolidados"""
    print("="*80)
    print("ANÁLISIS DE COLUMNAS - DATASETS CONSOLIDADOS")
    print("="*80)

    # Cargar solo las primeras filas para ver columnas
    print("\nCargando datasets...")
    df_metabric = pd.read_csv(METABRIC_FILE, nrows=5)
    print(f"  ✓ METABRIC: {len(df_metabric.columns)} columnas")

    df_scanb = pd.read_csv(SCANB_FILE, nrows=5)
    print(f"  ✓ SCAN-B: {len(df_scanb.columns)} columnas")

    df_tcga = pd.read_csv(TCGA_FILE, nrows=5)
    print(f"  ✓ TCGA_BRCA: {len(df_tcga.columns)} columnas")

    # Categorizar columnas
    print("\n" + "="*80)
    print("CATEGORIZACIÓN DE COLUMNAS POR DATASET")
    print("="*80)

    print("\n--- METABRIC ---")
    metabric_cats = categorize_columns(df_metabric.columns)
    for cat, cols in metabric_cats.items():
        if cols:
            print(f"  {cat.upper()}: {len(cols)} columnas")

    print("\n--- SCAN-B ---")
    scanb_cats = categorize_columns(df_scanb.columns)
    for cat, cols in scanb_cats.items():
        if cols:
            print(f"  {cat.upper()}: {len(cols)} columnas")

    print("\n--- TCGA_BRCA ---")
    tcga_cats = categorize_columns(df_tcga.columns)
    for cat, cols in tcga_cats.items():
        if cols:
            print(f"  {cat.upper()}: {len(cols)} columnas")

    # Encontrar columnas similares
    print("\n" + "="*80)
    print("COLUMNAS COMPARTIDAS O SIMILARES")
    print("="*80)

    matches = find_similar_columns(df_metabric.columns, df_scanb.columns, df_tcga.columns)

    # Filtrar solo las que están en al menos 2 datasets
    shared_matches = {k: v for k, v in matches.items()
                     if sum([len(v['metabric']) > 0, len(v['scanb']) > 0, len(v['tcga']) > 0]) >= 2}

    print(f"\nColumnas presentes en al menos 2 datasets: {len(shared_matches)}")

    # Columnas en los 3 datasets
    all_three = {k: v for k, v in matches.items()
                if len(v['metabric']) > 0 and len(v['scanb']) > 0 and len(v['tcga']) > 0}

    print(f"Columnas presentes en los 3 datasets: {len(all_three)}")

    # Guardar mapeo
    with open(MAPPING_FILE, 'w') as f:
        f.write("="*80 + "\n")
        f.write("MAPEO DE COLUMNAS ENTRE DATASETS\n")
        f.write("="*80 + "\n\n")

        f.write(f"Total de columnas únicas (normalizadas): {len(matches)}\n")
        f.write(f"Columnas compartidas (2+ datasets): {len(shared_matches)}\n")
        f.write(f"Columnas compartidas (3 datasets): {len(all_three)}\n\n")

        f.write("="*80 + "\n")
        f.write("COLUMNAS EN LOS 3 DATASETS\n")
        f.write("="*80 + "\n\n")
        for norm_col, datasets in sorted(all_three.items()):
            f.write(f"[{norm_col}]\n")
            f.write(f"  METABRIC: {datasets['metabric']}\n")
            f.write(f"  SCAN-B:   {datasets['scanb']}\n")
            f.write(f"  TCGA:     {datasets['tcga']}\n\n")

        f.write("="*80 + "\n")
        f.write("COLUMNAS EN 2 DATASETS\n")
        f.write("="*80 + "\n\n")
        two_datasets = {k: v for k, v in shared_matches.items() if k not in all_three}
        for norm_col, datasets in sorted(two_datasets.items()):
            f.write(f"[{norm_col}]\n")
            if datasets['metabric']:
                f.write(f"  METABRIC: {datasets['metabric']}\n")
            if datasets['scanb']:
                f.write(f"  SCAN-B:   {datasets['scanb']}\n")
            if datasets['tcga']:
                f.write(f"  TCGA:     {datasets['tcga']}\n")
            f.write("\n")

        f.write("="*80 + "\n")
        f.write("RESUMEN POR CATEGORÍA\n")
        f.write("="*80 + "\n\n")

        # Categorizar las columnas compartidas
        for cat_name in ['identifier', 'clinical', 'demographic', 'treatment', 'genomic', 'imaging', 'survival']:
            f.write(f"\n--- {cat_name.upper()} ---\n")
            for norm_col, datasets in sorted(all_three.items()):
                # Check if any column in this match belongs to this category
                all_cols = datasets['metabric'] + datasets['scanb'] + datasets['tcga']
                cats = categorize_columns(all_cols)
                if cats[cat_name]:
                    f.write(f"  {norm_col}\n")

    print(f"\n✓ Mapeo guardado en: {MAPPING_FILE}")

    # Mostrar resumen en pantalla
    print("\n" + "="*80)
    print("COLUMNAS EN LOS 3 DATASETS (Key columns)")
    print("="*80)
    for norm_col, datasets in sorted(all_three.items())[:20]:  # Mostrar primeras 20
        print(f"\n[{norm_col}]")
        print(f"  METABRIC: {', '.join(datasets['metabric'])}")
        print(f"  SCAN-B:   {', '.join(datasets['scanb'])}")
        print(f"  TCGA:     {', '.join(datasets['tcga'])}")

    if len(all_three) > 20:
        print(f"\n... y {len(all_three) - 20} columnas más (ver {MAPPING_FILE})")

def main():
    analyze_datasets()
    print("\n✓ Análisis completado!")

if __name__ == "__main__":
    main()
