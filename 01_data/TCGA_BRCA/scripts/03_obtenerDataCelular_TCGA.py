"""
Script REAL para obtener información de imágenes histopatológicas de TCGA-BRCA
Dataset: TCGA Breast Cancer (TCGA-BRCA)
Descarga: Metadatos de imágenes de láminas diagnósticas (Slide Images)
"""

import os
import json
import requests
import pandas as pd
from pathlib import Path

# Configuración
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "outputs_API_DEMO"
OUTPUT_DIR.mkdir(exist_ok=True)

# API Endpoints del GDC
FILES_ENDPOINT = "https://api.gdc.cancer.gov/files"

print("="*80)
print("   DESCARGA REAL DE METADATOS DE IMÁGENES: TCGA-BRCA")
print("   Fuente: GDC (Genomic Data Commons)")
print("   Tipo: Slide Images (Histopatología)")
print("="*80)

# -----------------------------------------------------------------------------
# PASO 1: BUSCAR IMÁGENES DE LÁMINAS DIAGNÓSTICAS
# -----------------------------------------------------------------------------
def search_slide_images():
    """Busca imágenes de láminas diagnósticas de TCGA-BRCA"""
    print(f"\n[1/3] Buscando imágenes de histopatología...")
    
    # Filtro para Slide Images de TCGA-BRCA
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
                    "value": ["Slide Image"]
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
        "cases.samples.sample_type",
        "cases.samples.tissue_type",
        "data_type",
        "data_format",
        "experimental_strategy",
        "created_datetime",
        "updated_datetime"
    ]
    
    params = {
        "filters": json.dumps(filters),
        "fields": ",".join(fields),
        "format": "JSON",
        "size": 5000  # Obtener hasta 5000 imágenes
    }
    
    try:
        print(f"  Consultando API del GDC...")
        response = requests.get(FILES_ENDPOINT, params=params, timeout=120)
        response.raise_for_status()
        
        data = response.json()
        hits = data['data']['hits']
        
        print(f"  ✓ Encontradas {len(hits)} imágenes de láminas diagnósticas")
        
        # Normalizar a DataFrame
        df = pd.json_normalize(hits)
        
        # Mostrar información
        total_size_gb = df['file_size'].sum() / (1024**3)
        print(f"  ✓ Tamaño total: {total_size_gb:.2f} GB")
        print(f"  ✓ Tamaño promedio por imagen: {df['file_size'].mean()/(1024**2):.1f} MB")
        
        return df
        
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 2: ANALIZAR METADATOS DE IMÁGENES
# -----------------------------------------------------------------------------
def analyze_slide_metadata(df_slides):
    """Analiza los metadatos de las imágenes"""
    print(f"\n[2/3] Analizando metadatos de imágenes...")
    
    if df_slides is None or df_slides.empty:
        return None
    
    try:
        # Crear DataFrame resumido
        summary_data = []
        
        for idx, row in df_slides.iterrows():
            file_info = {
                'file_id': row.get('file_id', ''),
                'file_name': row.get('file_name', ''),
                'file_size_mb': row.get('file_size', 0) / (1024**2),
                'data_format': row.get('data_format', ''),
                'patient_id': row.get('cases.0.submitter_id', '') if 'cases.0.submitter_id' in row else '',
                'case_id': row.get('cases.0.case_id', '') if 'cases.0.case_id' in row else '',
                'sample_type': row.get('cases.0.samples.0.sample_type', '') if 'cases.0.samples.0.sample_type' in row else '',
                'tissue_type': row.get('cases.0.samples.0.tissue_type', '') if 'cases.0.samples.0.tissue_type' in row else '',
                'created_date': row.get('created_datetime', '')
            }
            summary_data.append(file_info)
        
        df_summary = pd.DataFrame(summary_data)
        
        print(f"  ✓ Metadatos procesados: {df_summary.shape}")
        
        # Estadísticas
        print(f"\n  Estadísticas:")
        print(f"    - Total de imágenes: {len(df_summary)}")
        print(f"    - Pacientes únicos: {df_summary['patient_id'].nunique()}")
        
        if 'sample_type' in df_summary.columns:
            print(f"\n  Tipos de muestra:")
            print(df_summary['sample_type'].value_counts().head())
        
        if 'data_format' in df_summary.columns:
            print(f"\n  Formatos de archivo:")
            print(df_summary['data_format'].value_counts())
        
        return df_summary
        
    except Exception as e:
        print(f"  ✗ Error analizando metadatos: {e}")
        import traceback
        traceback.print_exc()
        return None

# -----------------------------------------------------------------------------
# PASO 3: GUARDAR ARCHIVOS DE SALIDA
# -----------------------------------------------------------------------------
def save_outputs(df_slides, df_summary):
    """Guarda los archivos de salida"""
    print(f"\n[3/3] Guardando archivos de salida...")
    
    try:
        # Guardar metadatos completos de imágenes
        if df_slides is not None and not df_slides.empty:
            output_file = OUTPUT_DIR / "tcga_brca_slide_images_full.csv"
            df_slides.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_slides.shape}")
        
        # Guardar resumen de metadatos
        if df_summary is not None and not df_summary.empty:
            output_file = OUTPUT_DIR / "tcga_brca_slide_images_summary.csv"
            df_summary.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_summary.shape}")
            
            # Mostrar primeras filas
            print(f"\n  Primeras filas del resumen:")
            display_cols = ['patient_id', 'file_name', 'file_size_mb', 'sample_type']
            display_cols = [col for col in display_cols if col in df_summary.columns]
            if display_cols:
                print(df_summary[display_cols].head(3).to_string())
        
        # Crear archivo de URLs de descarga
        if df_summary is not None and not df_summary.empty and 'file_id' in df_summary.columns:
            df_urls = df_summary[['file_id', 'patient_id', 'file_name']].copy()
            df_urls['download_url'] = df_urls['file_id'].apply(
                lambda x: f"https://api.gdc.cancer.gov/data/{x}"
            )
            
            output_file = OUTPUT_DIR / "tcga_brca_slide_images_download_urls.csv"
            df_urls.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Contiene URLs de descarga directa para cada imagen")
        
        print(f"\n✓ Todos los archivos guardados en: {OUTPUT_DIR}")
        
        # Información adicional
        print(f"\n📝 NOTAS IMPORTANTES:")
        print(f"  - Las imágenes NO fueron descargadas debido a su gran tamaño")
        print(f"  - Tamaño total estimado: {df_slides['file_size'].sum()/(1024**3):.1f} GB")
        print(f"  - Se generó un archivo con URLs de descarga directa")
        print(f"  - Para descargar imágenes individuales, usar:")
        print(f"    wget https://api.gdc.cancer.gov/data/[FILE_ID]")
        
    except Exception as e:
        print(f"  ✗ Error guardando archivos: {e}")
        import traceback
        traceback.print_exc()

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print("\nIniciando búsqueda de imágenes histopatológicas...\n")
    
    # 1. Buscar imágenes de láminas
    df_slides = search_slide_images()
    
    if df_slides is None or df_slides.empty:
        print("\n✗ No se encontraron imágenes. Abortando.")
        return
    
    # 2. Analizar metadatos
    df_summary = analyze_slide_metadata(df_slides)
    
    # 3. Guardar archivos
    save_outputs(df_slides, df_summary)
    
    print("\n" + "="*80)
    print("   DESCARGA DE METADATOS COMPLETADA")
    print("="*80)
    print(f"\nArchivos generados en: {OUTPUT_DIR}")
    print(f"\nPara análisis de imágenes, considerar:")
    print(f"  - Usar herramientas de análisis de imagen (QuPath, ImageJ)")
    print(f"  - Extraer características con deep learning (ResNet, VGG)")
    print(f"  - Aplicar segmentación de tejidos")

if __name__ == "__main__":
    main()