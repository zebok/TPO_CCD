"""
Script para analizar las listas de columnas y sugerir mapeos automáticamente
basándose en similitud de nombres y categorías semánticas.
"""

import re
from pathlib import Path
from difflib import SequenceMatcher
from collections import defaultdict

# Rutas
OUTPUT_DIR = Path(__file__).parent.parent / "output"  # 02_consolidacion/output/
METABRIC_LIST = OUTPUT_DIR / "lista_columnas_metabric.txt"
SCANB_LIST = OUTPUT_DIR / "lista_columnas_scanb.txt"
TCGA_LIST = OUTPUT_DIR / "lista_columnas_tcga_brca.txt"
OUTPUT_FILE = OUTPUT_DIR / "mapeo_sugerido.yaml"

def parse_column_list(file_path):
    """Extrae los nombres de columnas de un archivo de lista"""
    columns = []
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            # Buscar líneas con formato "N. COLUMN_NAME"
            match = re.match(r'^\d+\.\s+(.+)$', line)
            if match:
                columns.append(match.group(1))
    return columns

def normalize_name(name):
    """Normaliza un nombre de columna para comparación"""
    normalized = name.lower()
    normalized = re.sub(r'[_\s.-]+', '_', normalized)
    normalized = normalized.strip('_')
    return normalized

def similarity_score(str1, str2):
    """Calcula similitud entre dos strings (0-1)"""
    return SequenceMatcher(None, normalize_name(str1), normalize_name(str2)).ratio()

def categorize_column(col_name):
    """Categoriza una columna por su nombre"""
    col_lower = col_name.lower()

    # Identificadores
    if col_lower in ['patient_id', 'patient', 'sample', 'id']:
        return 'identifier'

    # Clínicos
    if any(x in col_lower for x in ['er_', 'pr_', 'her2', 'erbb2', 'subtype', 'grade', 'stage', 'ihc', 'pam50', 'claudin', 'intclust']):
        return 'clinical'

    # Demográficos
    if any(x in col_lower for x in ['age', 'race', 'gender', 'ethnicity', 'nationality', 'smoking', 'menopausal', 'demographic']):
        return 'demographic'

    # Tratamientos
    if any(x in col_lower for x in ['treatment', 'therapy', 'chemo', 'radiation', 'hormone', 'surgery', 'had_']):
        return 'treatment'

    # Supervivencia
    if any(x in col_lower for x in ['survival', 'vital', 'death', 'followup', 'os_', 'event', 'cohort']):
        return 'survival'

    # Tumor características
    if any(x in col_lower for x in ['tumor', 'lymph', 'node', 'size']):
        return 'tumor'

    # Imaging/Morfología
    if any(x in col_lower for x in ['nuc_', 'radius', 'texture', 'perimeter', 'area', 'smoothness',
                                     'compactness', 'concavity', 'symmetry', 'fractal', 'diagnosis']):
        return 'imaging'

    # Genes conocidos
    known_genes = ['esr1', 'pgr', 'erbb2', 'tp53', 'brca1', 'brca2', 'pik3ca', 'pten', 'akt1',
                   'mki67', 'gata3', 'foxa1', 'map3k1', 'kmt2c', 'cdh1', 'rb1', 'ncor1',
                   'macf1', 'arid1a', 'bap1']
    if col_lower in known_genes:
        return 'genomic_key'

    # Otros genes (GENE_N, nombres de pacientes como columnas en expression matrices)
    if re.match(r'^gene_\d+$', col_lower) or re.match(r'^scan-b-\d+$', col_lower) or \
       re.match(r'^tcga-[a-z0-9-]+$', col_lower) or re.match(r'^mb-\d+$', col_lower):
        return 'genomic_other'

    # Metadatos
    if any(x in col_lower for x in ['date', 'year', 'region', 'hospital', 'country', 'state', 'created']):
        return 'metadata'

    return 'other'

def find_matches(metabric_cols, scanb_cols, tcga_cols, min_similarity=0.7):
    """Encuentra columnas que matchean entre datasets"""

    matches = []

    # Categorizar todas las columnas
    metabric_by_cat = defaultdict(list)
    scanb_by_cat = defaultdict(list)
    tcga_by_cat = defaultdict(list)

    for col in metabric_cols:
        cat = categorize_column(col)
        metabric_by_cat[cat].append(col)

    for col in scanb_cols:
        cat = categorize_column(col)
        scanb_by_cat[cat].append(col)

    for col in tcga_cols:
        cat = categorize_column(col)
        tcga_by_cat[cat].append(col)

    # Buscar matches dentro de cada categoría
    all_categories = set(metabric_by_cat.keys()) | set(scanb_by_cat.keys()) | set(tcga_by_cat.keys())

    for category in all_categories:
        if category in ['genomic_other', 'other', 'metadata']:
            continue  # Skip categorías con muchas columnas no importantes

        m_cols = metabric_by_cat.get(category, [])
        s_cols = scanb_by_cat.get(category, [])
        t_cols = tcga_by_cat.get(category, [])

        # Buscar matches entre los 3 datasets
        all_cols = [(col, 'metabric') for col in m_cols] + \
                   [(col, 'scanb') for col in s_cols] + \
                   [(col, 'tcga') for col in t_cols]

        # Agrupar columnas similares
        used = set()
        for i, (col1, ds1) in enumerate(all_cols):
            if i in used:
                continue

            match_group = {
                'metabric': None,
                'scanb': None,
                'tcga': None,
                'category': category,
                'unified_name': normalize_name(col1)
            }
            match_group[ds1] = col1
            used.add(i)

            # Buscar columnas similares en otros datasets
            for j, (col2, ds2) in enumerate(all_cols[i+1:], start=i+1):
                if j in used or ds2 == ds1:
                    continue

                sim = similarity_score(col1, col2)
                if sim >= min_similarity:
                    match_group[ds2] = col2
                    used.add(j)

            # Solo agregar si hay al menos 2 datasets
            if sum(1 for v in [match_group['metabric'], match_group['scanb'], match_group['tcga']] if v) >= 2:
                matches.append(match_group)

    return matches

def generate_yaml_output(matches, output_file):
    """Genera archivo YAML con los mapeos sugeridos"""

    # Agrupar por categoría
    by_category = defaultdict(list)
    for match in matches:
        by_category[match['category']].append(match)

    with open(output_file, 'w') as f:
        f.write("# MAPEO SUGERIDO AUTOMÁTICAMENTE\n")
        f.write("# Revisa y ajusta según sea necesario\n")
        f.write("# Luego copia los mapeos relevantes a column_mapping_manual.yaml\n\n")

        # Orden de categorías
        category_order = ['identifier', 'clinical', 'demographic', 'tumor', 'survival',
                         'treatment', 'genomic_key', 'imaging']

        for category in category_order:
            if category not in by_category:
                continue

            f.write(f"\n{'='*80}\n")
            f.write(f"# {category.upper()}\n")
            f.write(f"{'='*80}\n\n")

            for match in sorted(by_category[category], key=lambda x: x['unified_name']):
                unified_name = match['unified_name']
                f.write(f"{unified_name}:\n")
                f.write(f"  metabric: {match['metabric'] or 'null'}\n")
                f.write(f"  scanb: {match['scanb'] or 'null'}\n")
                f.write(f"  tcga: {match['tcga'] or 'null'}\n")
                f.write(f"  tipo: {match['category']}\n\n")

def main():
    print("="*80)
    print("ANÁLISIS Y SUGERENCIA DE MAPEOS DE COLUMNAS")
    print("="*80)

    # Parsear listas de columnas
    print("\nCargando listas de columnas...")
    metabric_cols = parse_column_list(METABRIC_LIST)
    print(f"  ✓ METABRIC: {len(metabric_cols)} columnas")

    scanb_cols = parse_column_list(SCANB_LIST)
    print(f"  ✓ SCAN-B: {len(scanb_cols)} columnas")

    tcga_cols = parse_column_list(TCGA_LIST)
    print(f"  ✓ TCGA_BRCA: {len(tcga_cols)} columnas")

    # Encontrar matches
    print("\nBuscando columnas similares...")
    matches = find_matches(metabric_cols, scanb_cols, tcga_cols, min_similarity=0.7)
    print(f"  ✓ {len(matches)} grupos de columnas encontrados")

    # Contar por categoría
    by_cat = defaultdict(int)
    for match in matches:
        by_cat[match['category']] += 1

    print("\nColumnas por categoría:")
    for cat, count in sorted(by_cat.items()):
        print(f"  {cat}: {count}")

    # Generar YAML
    print(f"\nGenerando mapeo sugerido...")
    generate_yaml_output(matches, OUTPUT_FILE)
    print(f"  ✓ Archivo guardado: {OUTPUT_FILE}")

    # Mostrar preview
    print("\n" + "="*80)
    print("PREVIEW - PRIMEROS 15 MAPEOS")
    print("="*80)
    for i, match in enumerate(matches[:15]):
        print(f"\n{i+1}. [{match['unified_name']}] ({match['category']})")
        print(f"   METABRIC: {match['metabric']}")
        print(f"   SCAN-B:   {match['scanb']}")
        print(f"   TCGA:     {match['tcga']}")

    if len(matches) > 15:
        print(f"\n... y {len(matches) - 15} mapeos más (ver {OUTPUT_FILE})")

    print("\n" + "="*80)
    print("✓ ANÁLISIS COMPLETADO")
    print("="*80)
    print(f"\nRevisa el archivo: {OUTPUT_FILE}")
    print("Luego copia los mapeos relevantes a: column_mapping_manual.yaml")

if __name__ == "__main__":
    main()
