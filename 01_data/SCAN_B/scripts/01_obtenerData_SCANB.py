"""
Script REAL para descargar datos de SCAN-B desde NCBI GEO
Dataset: GSE96058 (SCAN-B Sweden Cohort)
Descarga: Series matrix (metadata) + Expression data (supplementary files)
"""

import os
import time
import pandas as pd
import urllib.request
import gzip
import shutil
from pathlib import Path
import re
import ssl
import requests

# Configurar contexto SSL para evitar problemas de certificados
ssl._create_default_https_context = ssl._create_unverified_context

print("="*80)
print("   DESCARGA REAL DE DATOS: SCAN-B (GSE96058)")
print("   Fuente: NCBI GEO (Gene Expression Omnibus)")
print("="*80)

# Configuración
GEO_ACCESSION = "GSE96058"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "outputs_API_DEMO"
OUTPUT_DIR.mkdir(exist_ok=True)

# URLs para descargar datos
# Método 1: Descargar el archivo SOFT completo (contiene metadata)
SOFT_URL = f"https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc={GEO_ACCESSION}&targ=self&form=text&view=full"

# Método 2: Archivos suplementarios (expression data)
SUPPL_BASE_URL = "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE96nnn/GSE96058/suppl"

# -----------------------------------------------------------------------------
# PASO 1: DESCARGAR METADATOS CLÍNICOS (ARCHIVO SUPLEMENTARIO)
# -----------------------------------------------------------------------------
def download_clinical_metadata():
    """Descarga el archivo series_matrix que contiene los metadatos clínicos"""
    print(f"\n[1/4] Descargando metadatos clínicos (series_matrix)...")

    # El archivo series_matrix contiene los metadatos de GEO
    # Hay dos plataformas, usamos GPL11154 que tiene más muestras
    metadata_filename = "GSE96058-GPL11154_series_matrix.txt.gz"
    metadata_url = f"https://ftp.ncbi.nlm.nih.gov/geo/series/GSE96nnn/GSE96058/matrix/{metadata_filename}"
    
    gz_file = OUTPUT_DIR / metadata_filename
    txt_file = OUTPUT_DIR / "GSE96058_series_matrix.txt"

    # Descargar archivo .gz si no existe
    if not txt_file.exists():
        if not gz_file.exists():
            print(f"  Descargando desde: {metadata_url}")
            print(f"  Destino: {gz_file}")
            
            try:
                response = requests.get(metadata_url, timeout=120, stream=True)
                response.raise_for_status()
                
                # Descargar con barra de progreso
                total_size = int(response.headers.get('content-length', 0))
                with open(gz_file, 'wb') as f:
                    if total_size == 0:
                        f.write(response.content)
                    else:
                        downloaded = 0
                        for chunk in response.iter_content(chunk_size=8192):
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0:
                                percent = (downloaded / total_size) * 100
                                print(f"\r  Progreso: {percent:.1f}% ({downloaded}/{total_size} bytes)", end='')
                print()  # Nueva línea
                print(f"  ✓ Descarga completada")
                
            except requests.exceptions.RequestException as e:
                print(f"  ✗ Error descargando: {e}")
                print(f"\n  Intentando método alternativo: descargar lista de muestras...")
                return download_sample_list()
        else:
            print(f"  ℹ Archivo comprimido ya existe: {gz_file}")

        # Descomprimir
        print(f"  Descomprimiendo archivo...")
        try:
            with gzip.open(gz_file, 'rb') as f_in:
                with open(txt_file, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)
            print(f"  ✓ Archivo descomprimido: {txt_file}")
        except Exception as e:
            print(f"  ✗ Error descomprimiendo: {e}")
            return None
    else:
        print(f"  ℹ Archivo ya existe: {txt_file}")

    return txt_file

def download_sample_list():
    """Método alternativo: descargar solo la lista de muestras desde el SOFT"""
    print(f"  Descargando información básica de muestras...")
    
    soft_url = f"https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc={GEO_ACCESSION}&targ=self&form=text&view=brief"
    soft_file = OUTPUT_DIR / f"{GEO_ACCESSION}_brief.soft"
    
    try:
        response = requests.get(soft_url, timeout=60)
        response.raise_for_status()
        
        with open(soft_file, 'w', encoding='utf-8') as f:
            f.write(response.text)
        
        print(f"  ✓ Descarga completada")
        
        # Extraer IDs de muestras
        sample_ids = []
        for line in response.text.split('\n'):
            if line.startswith('!Series_sample_id'):
                sample_id = line.split('=')[1].strip()
                sample_ids.append(sample_id)
        
        if sample_ids:
            # Crear un DataFrame básico con los IDs
            df = pd.DataFrame({'Sample_ID': sample_ids})
            csv_file = OUTPUT_DIR / "sample_list.csv"
            df.to_csv(csv_file, index=False)
            print(f"  ✓ Lista de {len(sample_ids)} muestras guardada en: {csv_file}")
            return csv_file
        else:
            print(f"  ✗ No se pudieron extraer IDs de muestras")
            return None
            
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 2: LEER METADATOS CLÍNICOS DESDE SERIES_MATRIX
# -----------------------------------------------------------------------------
def read_clinical_metadata(file_path):
    """Lee y parsea el archivo series_matrix.txt de GEO"""
    print(f"\n[2/4] Leyendo metadatos clínicos desde series_matrix...")

    try:
        # Leer el archivo series_matrix
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        # Extraer información de las muestras
        sample_ids = []
        sample_data = {}
        
        for line in lines:
            line = line.strip()
            
            # Extraer IDs de muestras
            if line.startswith('!Sample_geo_accession'):
                # Formato: !Sample_geo_accession\t"GSM1"\t"GSM2"\t...
                parts = line.split('\t')
                sample_ids = [p.strip('"') for p in parts[1:] if p.strip('"')]
                print(f"  ✓ Encontrados {len(sample_ids)} IDs de muestras")
            
            # Extraer características de las muestras
            elif line.startswith('!Sample_characteristics_ch1'):
                # Formato: !Sample_characteristics_ch1\t"key: value"\t"key: value"\t...
                parts = line.split('\t')
                values = [p.strip('"') for p in parts[1:] if p.strip('"')]
                
                # Parsear key: value
                if values and ':' in values[0]:
                    key = values[0].split(':')[0].strip()
                    if key not in sample_data:
                        sample_data[key] = []
                    
                    for val in values:
                        if ':' in val:
                            sample_data[key].append(val.split(':', 1)[1].strip())
                        else:
                            sample_data[key].append('')
            
            # Otros campos útiles
            elif line.startswith('!Sample_title'):
                parts = line.split('\t')
                values = [p.strip('"') for p in parts[1:] if p.strip('"')]
                sample_data['Sample_title'] = values
            
            elif line.startswith('!Sample_source_name_ch1'):
                parts = line.split('\t')
                values = [p.strip('"') for p in parts[1:] if p.strip('"')]
                sample_data['Sample_source'] = values
        
        # Crear DataFrame
        if sample_ids:
            df = pd.DataFrame({'Sample_ID': sample_ids})
            
            # Agregar las características
            for key, values in sample_data.items():
                if len(values) == len(sample_ids):
                    df[key] = values
                else:
                    print(f"  ⚠ Advertencia: {key} tiene {len(values)} valores, esperados {len(sample_ids)}")
            
            print(f"  ✓ Metadatos parseados: {df.shape}")
            print(f"  ✓ Columnas encontradas ({len(df.columns)}): {list(df.columns)[:10]}...")
            
            # Mostrar primeras filas
            print(f"\n  Primeras filas:")
            print(df.head(3).to_string())
            
            return df
        else:
            print(f"  ✗ No se encontraron IDs de muestras en el archivo")
            return None

    except Exception as e:
        print(f"  ✗ Error leyendo archivo: {e}")
        import traceback
        traceback.print_exc()
        return None


# -----------------------------------------------------------------------------
# PASO 3: DESCARGAR ARCHIVOS SUPLEMENTARIOS (EXPRESSION DATA)
# -----------------------------------------------------------------------------
def download_supplementary_files():
    """
    Descarga archivos suplementarios de expresión
    Nota: GEO suele tener archivos grandes, esto puede tardar
    """
    print(f"\n[3/4] Buscando archivos suplementarios de expresión...")

    # Lista de archivos comunes en este dataset (según documentación GEO)
    suppl_files = [
        "GSE96058_gene_expression_3273_samples_and_136_replicates_transformed.csv.gz",
    ]

    downloaded_files = []

    for filename in suppl_files:
        url = f"{SUPPL_BASE_URL}/{filename}"
        output_path = OUTPUT_DIR / filename

        print(f"\n  Archivo: {filename}")

        # Este archivo es muy grande (~700MB), dar opción de no descargarlo
        print(f"  ⚠ ADVERTENCIA: Este archivo es muy grande (~700MB)")
        print(f"  Descarga omitida por defecto para ahorrar tiempo/espacio")
        print(f"  Si necesitas expresión génica completa, descomenta el código de descarga")

        # Descomenta esto si realmente quieres descargar:
        # if not output_path.exists():
        #     success = download_file(url, output_path)
        #     if success:
        #         downloaded_files.append(output_path)
        # else:
        #     print(f"  ℹ Archivo ya existe: {output_path}")
        #     downloaded_files.append(output_path)

    return downloaded_files

# -----------------------------------------------------------------------------
# PASO 4: GENERAR ARCHIVOS DE SALIDA LIMPIOS
# -----------------------------------------------------------------------------
def generate_clean_outputs(df_metadata):
    """Genera archivos limpios y estructurados"""
    print(f"\n[4/4] Generando archivos de salida limpios...")

    if df_metadata is None or df_metadata.empty:
        print(f"  ✗ No hay datos para procesar")
        return

    try:
        # Guardar metadatos clínicos completos
        output_file = OUTPUT_DIR / "scanb_clinical_metadata.csv"
        df_metadata.to_csv(output_file, index=False)
        print(f"  ✓ Guardado: {output_file}")
        print(f"    Shape: {df_metadata.shape}")

        # Intentar extraer campos demográficos si existen
        demo_cols = [col for col in df_metadata.columns
                     if any(x in col.lower() for x in ['age', 'gender', 'race', 'ethnicity', 'sex'])]

        if demo_cols:
            df_demographics = df_metadata[['Sample_ID'] + demo_cols].copy()
            output_file = OUTPUT_DIR / "scanb_demographics.csv"
            df_demographics.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_demographics.shape}")

        # Intentar extraer campos clínicos
        clinical_cols = [col for col in df_metadata.columns
                        if any(x in col.lower() for x in ['tumor', 'grade', 'stage', 'lymph', 'er', 'pr', 'her2', 'cancer', 'breast'])]

        if clinical_cols:
            df_clinical = df_metadata[['Sample_ID'] + clinical_cols].copy()
            output_file = OUTPUT_DIR / "scanb_clinical.csv"
            df_clinical.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_clinical.shape}")

        print(f"\n✓ Todos los archivos guardados en: {OUTPUT_DIR}")

    except Exception as e:
        print(f"  ✗ Error generando outputs: {e}")
        import traceback
        traceback.print_exc()


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print("\nIniciando descarga...")

    # 1. Descargar metadatos clínicos
    metadata_file = download_clinical_metadata()

    if metadata_file is None:
        print("\n✗ No se pudo descargar los metadatos. Abortando.")
        return

    # 2. Leer metadatos
    df_metadata = read_clinical_metadata(metadata_file)

    if df_metadata is None or df_metadata.empty:
        print("\n✗ No se pudieron leer los metadatos.")
        return

    # 3. Descargar archivos suplementarios (opcional)
    suppl_files = download_supplementary_files()

    # 4. Generar outputs limpios
    generate_clean_outputs(df_metadata)

    print("\n" + "="*80)
    print("   DESCARGA COMPLETADA")
    print("="*80)
    print(f"\nArchivos generados en: {OUTPUT_DIR}")
    print(f"\nNOTA: Los archivos de expresión génica completa NO fueron descargados")
    print(f"      debido a su tamaño (~700MB). Si los necesitas, edita el script")
    print(f"      y descomenta la sección de descarga en download_supplementary_files()")

if __name__ == "__main__":
    main()
