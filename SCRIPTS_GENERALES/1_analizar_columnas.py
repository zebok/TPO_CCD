import pandas as pd
import os

# CONFIGURACIÓN
INPUT_CSV = "../../1_metadata_gdc/Outputs/gdc_casos_metadata.csv"
OUTPUT_FILE = "../Outputs/columnas_casos.txt"

def main():
    if not os.path.exists(INPUT_CSV):
        print(f"Error: No encuentro {INPUT_CSV}")
        return

    print(f"Leyendo {INPUT_CSV}...")
    df = pd.read_csv(INPUT_CSV, low_memory=False)

    total_filas = len(df)
    total_cols = len(df.columns)
    print(f"Filas: {total_filas}, Columnas: {total_cols}")

    print(f"\nAnalizando nulos por columna...")

    # Calcular nulos por columna
    resultados = []
    for col in df.columns:
        nulos = df[col].isna().sum()
        no_nulos = total_filas - nulos
        pct_lleno = (no_nulos / total_filas) * 100
        resultados.append({
            'columna': col,
            'nulos': nulos,
            'no_nulos': no_nulos,
            'pct_lleno': pct_lleno
        })

    # Ordenar por porcentaje lleno (descendente)
    resultados.sort(key=lambda x: x['pct_lleno'], reverse=True)

    # Escribir archivo
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(f"ANÁLISIS DE COLUMNAS - {INPUT_CSV}\n")
        f.write(f"{'='*80}\n")
        f.write(f"Total filas: {total_filas}\n")
        f.write(f"Total columnas: {total_cols}\n")
        f.write(f"{'='*80}\n\n")

        # Columnas primarias (sin índice, nivel 0)
        f.write("COLUMNAS PRIMARIAS (más importantes):\n")
        f.write(f"{'-'*80}\n")
        primarias = [r for r in resultados if '[' not in r['columna'] and '.' not in r['columna']]
        for r in primarias:
            f.write(f"{r['columna']:50} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Columnas de nivel 1 (demographic, project, etc.)
        f.write(f"\n\nCOLUMNAS DE NIVEL 1 (demographic, project, etc.):\n")
        f.write(f"{'-'*80}\n")
        nivel1 = [r for r in resultados if '[' not in r['columna'] and '.' in r['columna'] and r['columna'].count('.') == 1]
        for r in nivel1:
            f.write(f"{r['columna']:50} | Lleno: {r['pct_lleno']:6.1f}% | No nulos: {r['no_nulos']:5}/{total_filas}\n")

        # Resumen de columnas con alto % de datos
        f.write(f"\n\nCOLUMNAS CON >80% DE DATOS (más útiles):\n")
        f.write(f"{'-'*80}\n")
        utiles = [r for r in resultados if r['pct_lleno'] >= 80]
        for r in utiles:
            f.write(f"{r['columna']:70} | Lleno: {r['pct_lleno']:6.1f}%\n")

        # Resumen de columnas con 50-80% de datos
        f.write(f"\n\nCOLUMNAS CON 50-80% DE DATOS:\n")
        f.write(f"{'-'*80}\n")
        medias = [r for r in resultados if 50 <= r['pct_lleno'] < 80]
        for r in medias:
            f.write(f"{r['columna']:70} | Lleno: {r['pct_lleno']:6.1f}%\n")

        # Todas las columnas ordenadas
        f.write(f"\n\n{'='*80}\n")
        f.write("TODAS LAS COLUMNAS (ordenadas por % de datos):\n")
        f.write(f"{'='*80}\n\n")
        for r in resultados:
            f.write(f"{r['columna']:70} | Lleno: {r['pct_lleno']:6.1f}% | Nulos: {r['nulos']}\n")

    print(f"\n¡Análisis completado!")
    print(f"Resultados guardados en: {OUTPUT_FILE}")

    # Resumen en consola
    print(f"\nRESUMEN:")
    print(f"  Columnas con >80% datos: {len([r for r in resultados if r['pct_lleno'] >= 80])}")
    print(f"  Columnas con 50-80% datos: {len([r for r in resultados if 50 <= r['pct_lleno'] < 80])}")
    print(f"  Columnas con <50% datos: {len([r for r in resultados if r['pct_lleno'] < 50])}")

if __name__ == "__main__":
    main()
