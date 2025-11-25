"""
Script REAL para descargar datos de expresión génica de TCGA-BRCA desde GDC API
Dataset: TCGA Breast Cancer (TCGA-BRCA)
Descarga: Datos de RNA-Seq (Gene Expression Quantification)
"""

import os
import json
import requests
import pandas as pd
from pathlib import Path
import time

# Configuración
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "outputs_API_DEMO"
OUTPUT_DIR.mkdir(exist_ok=True)

# API Endpoints del GDC
FILES_ENDPOINT = "https://api.gdc.cancer.gov/files"

print("="*80)
print("   DESCARGA REAL DE DATOS GENÓMICOS: TCGA-BRCA")
print("   Fuente: GDC (Genomic Data Commons)")
print("   Tipo: RNA-Seq Gene Expression Quantification")
print("="*80)

# -----------------------------------------------------------------------------
# PASO 1: BUSCAR ARCHIVOS DE EXPRESIÓN GÉNICA
# -----------------------------------------------------------------------------
def search_gene_expression_files():
    """Busca archivos de expresión génica de TCGA-BRCA"""
    print(f"\n[1/4] Buscando archivos de expresión génica...")
    
    # Filtro para RNA-Seq de TCGA-BRCA
    filters = {
        "op": "and",
        "content": [
            {
                "op": "in",
                "content": {
                    "field": "cases.project.project_id",
                    "value": ["TCGA-BRCA"]
                }
            },
            {
                "op": "in",
                "content": {
                    "field": "files.data_type",
                    "value": ["Gene Expression Quantification"]
                }
            },
            {
                "op": "in",
                "content": {
                    "field": "files.analysis.workflow_type",
                    "value": ["STAR - Counts"]
                }
            }
        ]
    }
    
    # Campos que queremos obtener
    fields = [
        "file_id",
        "file_name",
        "file_size",
        "cases.submitter_id",
        "cases.case_id",
        "data_type",
        "data_format",
        "analysis.workflow_type"
    ]
    
    params = {
        "filters": json.dumps(filters),
        "fields": ",".join(fields),
        "format": "JSON",
        "size": 2000  # Obtener hasta 2000 archivos
    }
    
    try:
        print(f"  Consultando API del GDC...")
        response = requests.get(FILES_ENDPOINT, params=params, timeout=120)
        response.raise_for_status()
        
        data = response.json()
        hits = data['data']['hits']
        
        print(f"  ✓ Encontrados {len(hits)} archivos de expresión génica")
        
        # Normalizar a DataFrame
        df = pd.json_normalize(hits)
        
        # Mostrar información
        total_size_gb = df['file_size'].sum() / (1024**3)
        print(f"  ✓ Tamaño total: {total_size_gb:.2f} GB")
        
        return df
        
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 2: DESCARGAR MUESTRA DE ARCHIVOS (PRIMEROS 10)
# -----------------------------------------------------------------------------
def download_sample_files(df_files, n_samples=10):
    """Descarga una muestra de archivos de expresión génica"""
    print(f"\n[2/4] Descargando muestra de archivos ({n_samples} archivos)...")
    print(f"  ⚠ NOTA: Descarga completa requeriría ~{df_files['file_size'].sum()/(1024**3):.1f} GB")
    print(f"  ⚠ Descargando solo {n_samples} archivos como demostración")
    
    if df_files is None or df_files.empty:
        return []
    
    # Directorio para archivos descargados
    download_dir = OUTPUT_DIR / "gene_expression_files"
    download_dir.mkdir(exist_ok=True)
    
    downloaded_files = []
    
    # Descargar solo los primeros n_samples archivos
    for idx, row in df_files.head(n_samples).iterrows():
        file_id = row['file_id']
        file_name = row['file_name']
        file_size_mb = row['file_size'] / (1024**2)
        
        print(f"  [{idx+1}/{n_samples}] Descargando: {file_name} ({file_size_mb:.1f} MB)")
        
        # URL de descarga
        download_url = f"https://api.gdc.cancer.gov/data/{file_id}"
        
        try:
            response = requests.get(download_url, timeout=300, stream=True)
            response.raise_for_status()
            
            # Guardar archivo
            output_path = download_dir / file_name
            with open(output_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            print(f"      ✓ Descargado: {output_path}")
            downloaded_files.append(output_path)
            
            # Pequeña pausa para no saturar la API
            time.sleep(0.5)
            
        except Exception as e:
            print(f"      ✗ Error descargando {file_name}: {e}")
    
    return downloaded_files

# -----------------------------------------------------------------------------
# PASO 3: PROCESAR ARCHIVOS Y CREAR MATRIZ DE EXPRESIÓN
# -----------------------------------------------------------------------------
def process_expression_files(downloaded_files):
    """Procesa archivos TSV y crea matriz de expresión"""
    print(f"\n[3/4] Procesando archivos de expresión...")
    
    if not downloaded_files:
        print(f"  ⚠ No hay archivos para procesar")
        return None
    
    try:
        expression_data = {}
        
        for file_path in downloaded_files:
            print(f"  Procesando: {file_path.name}")
            
            # Leer archivo TSV
            df = pd.read_csv(file_path, sep='\t', comment='#')
            
            # Extraer ID del paciente del nombre del archivo
            patient_id = file_path.stem.split('.')[0]
            
            # Guardar conteos de genes
            # Formato típico: gene_id, gene_name, gene_type, unstranded, stranded_first, stranded_second, tpm_unstranded, fpkm_unstranded, fpkm_uq_unstranded
            if 'gene_name' in df.columns and 'tpm_unstranded' in df.columns:
                gene_expression = df.set_index('gene_name')['tpm_unstranded']
                expression_data[patient_id] = gene_expression
            elif 'gene_id' in df.columns and 'unstranded' in df.columns:
                gene_expression = df.set_index('gene_id')['unstranded']
                expression_data[patient_id] = gene_expression
        
        if expression_data:
            # Crear DataFrame con todos los pacientes
            df_expression = pd.DataFrame(expression_data)
            
            print(f"  ✓ Matriz de expresión creada: {df_expression.shape}")
            print(f"    Genes: {df_expression.shape[0]}")
            print(f"    Muestras: {df_expression.shape[1]}")
            
            return df_expression
        else:
            print(f"  ✗ No se pudo crear matriz de expresión")
            return None
            
    except Exception as e:
        print(f"  ✗ Error procesando archivos: {e}")
        import traceback
        traceback.print_exc()
        return None

# -----------------------------------------------------------------------------
# PASO 4: GUARDAR ARCHIVOS DE SALIDA
# -----------------------------------------------------------------------------
def save_outputs(df_files, df_expression):
    """Guarda los archivos de salida"""
    print(f"\n[4/4] Guardando archivos de salida...")
    
    try:
        # Guardar lista de archivos disponibles
        if df_files is not None and not df_files.empty:
            output_file = OUTPUT_DIR / "tcga_brca_gene_expression_files_list.csv"
            df_files.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_files.shape}")
        
        # Guardar matriz de expresión
        if df_expression is not None and not df_expression.empty:
            output_file = OUTPUT_DIR / "tcga_brca_gene_expression_matrix.csv"
            df_expression.to_csv(output_file)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_expression.shape}")
            
            # Guardar también versión transpuesta (muestras en filas)
            output_file_t = OUTPUT_DIR / "tcga_brca_gene_expression_samples.csv"
            df_expression.T.to_csv(output_file_t)
            print(f"  ✓ Guardado (transpuesto): {output_file_t}")
        
        print(f"\n✓ Todos los archivos guardados en: {OUTPUT_DIR}")
        
    except Exception as e:
        print(f"  ✗ Error guardando archivos: {e}")
        import traceback
        traceback.print_exc()

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print("\nIniciando descarga de datos genómicos...\n")
    
    # 1. Buscar archivos de expresión génica
    df_files = search_gene_expression_files()
    
    if df_files is None or df_files.empty:
        print("\n✗ No se encontraron archivos de expresión génica. Abortando.")
        return
    
    # 2. Descargar muestra de archivos
    downloaded_files = download_sample_files(df_files, n_samples=10)
    
    # 3. Procesar archivos y crear matriz
    df_expression = process_expression_files(downloaded_files)
    
    # 4. Guardar archivos
    save_outputs(df_files, df_expression)
    
    print("\n" + "="*80)
    print("   DESCARGA COMPLETADA")
    print("="*80)
    print(f"\nArchivos generados en: {OUTPUT_DIR}")
    print(f"\nNOTA: Se descargaron solo 10 archivos de muestra.")
    print(f"      Para descargar todos los archivos, modifica n_samples en download_sample_files()")

if __name__ == "__main__":
    main()