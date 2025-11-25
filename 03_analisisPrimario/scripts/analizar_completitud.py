"""
Script para analizar el porcentaje de completitud de las columnas
en el dataset consolidado final.
"""

import pandas as pd
from pathlib import Path

# CONFIGURACIÓN
SCRIPT_DIR = Path(__file__).parent  # 03_analisisPrimario/scripts/
BASE_DIR = SCRIPT_DIR.parent.parent  # TPO_CCD/
INPUT_CSV = BASE_DIR / "02_consolidacion" / "output" / "dataset_consolidado_final.csv"
OUTPUT_FILE = SCRIPT_DIR.parent / "output" / "analisis_completitud.txt"

def main():
    if not INPUT_CSV.exists():
        print(f"Error: No encuentro {INPUT_CSV}")
        return

    print(f"Leyendo {INPUT_CSV}...")
    df = pd.read_csv(INPUT_CSV, low_memory=False)

    total_filas = len(df)
    total_cols = len(df.columns)
    print(f"Filas: {total_filas}, Columnas: {total_cols}")

    print(f"\nAnalizando completitud por columna...")

    # Calcular completitud por columna
    resultados = []
    for col in df.columns:
        nulos = df[col].isna().sum()
        no_nulos = total_filas - nulos
        pct_lleno = (no_nulos / total_filas) * 100

        # Calcular completitud por dataset
        completitud_por_dataset = {}
        for dataset in ['METABRIC', 'SCANB', 'TCGA']:
            mask = df['dataset_source'] == dataset
            if mask.any():
                total_ds = mask.sum()
                no_nulos_ds = df.loc[mask, col].notna().sum()
                pct_ds = (no_nulos_ds / total_ds) * 100
                completitud_por_dataset[dataset] = {
                    'total': total_ds,
                    'no_nulos': no_nulos_ds,
                    'pct': pct_ds
                }

        resultados.append({
            'columna': col,
            'nulos': nulos,
            'no_nulos': no_nulos,
            'pct_lleno': pct_lleno,
            'por_dataset': completitud_por_dataset
        })

    # Ordenar por porcentaje lleno (descendente)
    resultados.sort(key=lambda x: x['pct_lleno'], reverse=True)

    # Escribir archivo
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(f"ANÁLISIS DE COMPLETITUD - DATASET CONSOLIDADO FINAL\n")
        f.write(f"{'='*100}\n")
        f.write(f"Total de registros: {total_filas}\n")
        f.write(f"Total de columnas: {total_cols}\n")
        f.write(f"\nDistribución por dataset:\n")
        for dataset in ['METABRIC', 'SCANB', 'TCGA']:
            count = (df['dataset_source'] == dataset).sum()
            pct = (count / total_filas) * 100
            f.write(f"  {dataset}: {count} registros ({pct:.1f}%)\n")
        f.write(f"{'='*100}\n\n")

        # Columnas con 100% de datos
        f.write("COLUMNAS CON 100% DE COMPLETITUD:\n")
        f.write(f"{'-'*100}\n")
        completas = [r for r in resultados if r['pct_lleno'] == 100]
        for r in completas:
            f.write(f"{r['columna']:40} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Columnas con >80% de datos
        f.write(f"\n\nCOLUMNAS CON >80% DE COMPLETITUD (Muy útiles):\n")
        f.write(f"{'-'*100}\n")
        muy_utiles = [r for r in resultados if 80 <= r['pct_lleno'] < 100]
        for r in muy_utiles:
            f.write(f"{r['columna']:40} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Columnas con 50-80% de datos
        f.write(f"\n\nCOLUMNAS CON 50-80% DE COMPLETITUD (Moderadamente útiles):\n")
        f.write(f"{'-'*100}\n")
        medias = [r for r in resultados if 50 <= r['pct_lleno'] < 80]
        for r in medias:
            f.write(f"{r['columna']:40} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Columnas con <50% de datos
        f.write(f"\n\nCOLUMNAS CON <50% DE COMPLETITUD (Limitadas):\n")
        f.write(f"{'-'*100}\n")
        bajas = [r for r in resultados if r['pct_lleno'] < 50]
        for r in bajas:
            f.write(f"{r['columna']:40} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Análisis detallado por dataset
        f.write(f"\n\n{'='*100}\n")
        f.write("COMPLETITUD POR DATASET (columnas más relevantes)\n")
        f.write(f"{'='*100}\n\n")

        # Solo mostrar columnas con al menos 50% de completitud general
        relevantes = [r for r in resultados if r['pct_lleno'] >= 50 and r['columna'] != 'dataset_source']

        for r in relevantes:
            f.write(f"\n{r['columna']} (Completitud global: {r['pct_lleno']:.1f}%)\n")
            f.write(f"{'-'*100}\n")
            for dataset, info in r['por_dataset'].items():
                f.write(f"  {dataset:10} | {info['no_nulos']:4}/{info['total']:4} registros ({info['pct']:6.1f}%)\n")

        # Todas las columnas ordenadas
        f.write(f"\n\n{'='*100}\n")
        f.write("TODAS LAS COLUMNAS (ordenadas por % de completitud)\n")
        f.write(f"{'='*100}\n\n")
        for r in resultados:
            f.write(f"{r['columna']:40} | Lleno: {r['pct_lleno']:6.1f}% | Nulos: {r['nulos']:4} | No nulos: {r['no_nulos']:5}\n")

        # Resumen por categoría
        f.write(f"\n\n{'='*100}\n")
        f.write("RESUMEN POR CATEGORÍA DE COLUMNA\n")
        f.write(f"{'='*100}\n\n")

        categorias = {
            'Identificadores': ['id_paciente', 'dataset_source'],
            'Clínicos': [r['columna'] for r in resultados if any(x in r['columna'] for x in ['er_status', 'pr_status', 'her2_status', 'tumor', 'lymph'])],
            'Demográficos': [r['columna'] for r in resultados if any(x in r['columna'] for x in ['age', 'race', 'gender', 'menopausal'])],
            'Supervivencia': [r['columna'] for r in resultados if any(x in r['columna'] for x in ['survival', 'vital'])],
            'Tratamientos': [r['columna'] for r in resultados if any(x in r['columna'] for x in ['chemotherapy', 'hormone', 'radio', 'surgery'])],
            'Expresión génica': [r['columna'] for r in resultados if 'expression' in r['columna']],
            'Imaging': [r['columna'] for r in resultados if any(x in r['columna'] for x in ['radius', 'texture', 'area', 'smoothness', 'compactness', 'concavity', 'symmetry', 'fractal', 'diagnosis']) and r['columna'] != 'age_at_diagnosis']
        }

        for cat_name, cols in categorias.items():
            if cols:
                f.write(f"\n{cat_name}:\n")
                f.write(f"{'-'*100}\n")
                cat_results = [r for r in resultados if r['columna'] in cols]
                for r in cat_results:
                    f.write(f"  {r['columna']:40} | {r['pct_lleno']:6.1f}% completo\n")

    print(f"\n✓ Análisis completado!")
    print(f"Resultados guardados en: {OUTPUT_FILE}")

    # Resumen en consola
    print(f"\n{'='*80}")
    print("RESUMEN DE COMPLETITUD:")
    print(f"{'='*80}")
    print(f"  Columnas con 100% datos:    {len([r for r in resultados if r['pct_lleno'] == 100])}")
    print(f"  Columnas con >80% datos:    {len([r for r in resultados if 80 <= r['pct_lleno'] < 100])}")
    print(f"  Columnas con 50-80% datos:  {len([r for r in resultados if 50 <= r['pct_lleno'] < 80])}")
    print(f"  Columnas con <50% datos:    {len([r for r in resultados if r['pct_lleno'] < 50])}")

    print(f"\nColumnas más completas (top 10):")
    for i, r in enumerate(resultados[:10], 1):
        print(f"  {i:2}. {r['columna']:40} {r['pct_lleno']:6.1f}%")

if __name__ == "__main__":
    main()
