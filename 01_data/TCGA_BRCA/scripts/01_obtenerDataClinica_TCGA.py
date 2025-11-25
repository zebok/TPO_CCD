"""
Script REAL para descargar datos clínicos de TCGA-BRCA desde GDC API
Dataset: TCGA Breast Cancer (TCGA-BRCA)
Descarga: Metadatos clínicos, demográficos y de tratamiento
"""

import os
import json
import time
import requests
import pandas as pd
from pathlib import Path

# Configuración
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "outputs_API_DEMO"
OUTPUT_DIR.mkdir(exist_ok=True)

# API Endpoints del GDC
CASES_ENDPOINT = "https://api.gdc.cancer.gov/cases"
FILES_ENDPOINT = "https://api.gdc.cancer.gov/files"

print("="*80)
print("   DESCARGA REAL DE DATOS CLÍNICOS: TCGA-BRCA")
print("   Fuente: GDC (Genomic Data Commons)")
print("="*80)

# -----------------------------------------------------------------------------
# PASO 1: OBTENER CASOS (PACIENTES) DE TCGA-BRCA
# -----------------------------------------------------------------------------
def get_tcga_brca_cases():
    """Obtiene información de casos de TCGA-BRCA"""
    print(f"\n[1/4] Obteniendo lista de casos de TCGA-BRCA...")
    
    # Filtro para TCGA-BRCA
    filters = {
        "op": "and",
        "content": [
            {
                "op": "in",
                "content": {
                    "field": "cases.project.project_id",
                    "value": ["TCGA-BRCA"]
                }
            }
        ]
    }
    
    # Campos que queremos obtener
    fields = [
        "case_id",
        "submitter_id",
        "primary_site",
        "disease_type",
        "demographic.gender",
        "demographic.race",
        "demographic.ethnicity",
        "demographic.vital_status",
        "demographic.days_to_death",
        "demographic.days_to_birth",
        "diagnoses.age_at_diagnosis",
        "diagnoses.tumor_stage",
        "diagnoses.tumor_grade",
        "diagnoses.primary_diagnosis",
        "diagnoses.tissue_or_organ_of_origin",
        "diagnoses.morphology",
        "diagnoses.days_to_last_follow_up",
        "exposures.alcohol_history",
        "exposures.cigarettes_per_day",
        "treatments.treatment_type",
        "treatments.therapeutic_agents"
    ]
    
    params = {
        "filters": json.dumps(filters),
        "fields": ",".join(fields),
        "format": "JSON",
        "size": 10000  # Máximo permitido por página
    }
    
    try:
        print(f"  Consultando API del GDC...")
        response = requests.get(CASES_ENDPOINT, params=params, timeout=120)
        response.raise_for_status()
        
        data = response.json()
        hits = data['data']['hits']
        
        print(f"  ✓ Obtenidos {len(hits)} casos de TCGA-BRCA")
        
        # Normalizar JSON a DataFrame
        df = pd.json_normalize(hits)
        
        return df
        
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 2: PROCESAR Y LIMPIAR DATOS CLÍNICOS
# -----------------------------------------------------------------------------
def process_clinical_data(df):
    """Procesa y limpia los datos clínicos"""
    print(f"\n[2/4] Procesando datos clínicos...")
    
    if df is None or df.empty:
        print(f"  ✗ No hay datos para procesar")
        return None
    
    try:
        # Renombrar columnas para mayor claridad
        rename_map = {
            'case_id': 'case_id',
            'submitter_id': 'patient_id',
            'primary_site': 'primary_site',
            'disease_type': 'disease_type'
        }
        
        # Aplicar renombrado solo a columnas que existen
        existing_cols = {k: v for k, v in rename_map.items() if k in df.columns}
        df = df.rename(columns=existing_cols)
        
        print(f"  ✓ Datos procesados: {df.shape}")
        print(f"  ✓ Columnas disponibles: {len(df.columns)}")
        
        # Mostrar primeras filas
        print(f"\n  Primeras filas:")
        display_cols = [col for col in ['patient_id', 'primary_site', 'disease_type'] if col in df.columns]
        if display_cols:
            print(df[display_cols].head(3).to_string())
        
        return df
        
    except Exception as e:
        print(f"  ✗ Error procesando datos: {e}")
        import traceback
        traceback.print_exc()
        return None

# -----------------------------------------------------------------------------
# PASO 3: EXTRAER DATOS DEMOGRÁFICOS
# -----------------------------------------------------------------------------
def extract_demographics(df):
    """Extrae información demográfica"""
    print(f"\n[3/4] Extrayendo datos demográficos...")
    
    if df is None or df.empty:
        return None
    
    try:
        # Columnas demográficas
        demo_cols = [col for col in df.columns if 'demographic' in col.lower()]
        
        if demo_cols:
            base_cols = ['case_id', 'patient_id'] if 'patient_id' in df.columns else ['case_id']
            base_cols = [col for col in base_cols if col in df.columns]
            
            df_demo = df[base_cols + demo_cols].copy()
            
            # Calcular edad en años si tenemos days_to_birth
            if 'demographic.days_to_birth' in df_demo.columns:
                df_demo['age_years'] = abs(df_demo['demographic.days_to_birth'] / 365.25)
            
            print(f"  ✓ Datos demográficos extraídos: {df_demo.shape}")
            return df_demo
        else:
            print(f"  ⚠ No se encontraron columnas demográficas")
            return None
            
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 4: GUARDAR ARCHIVOS DE SALIDA
# -----------------------------------------------------------------------------
def save_outputs(df_clinical, df_demographics):
    """Guarda los archivos de salida"""
    print(f"\n[4/4] Guardando archivos de salida...")
    
    try:
        # Guardar datos clínicos completos
        if df_clinical is not None and not df_clinical.empty:
            output_file = OUTPUT_DIR / "tcga_brca_clinical_full.csv"
            df_clinical.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_clinical.shape}")
        
        # Guardar datos demográficos
        if df_demographics is not None and not df_demographics.empty:
            output_file = OUTPUT_DIR / "tcga_brca_demographics.csv"
            df_demographics.to_csv(output_file, index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_demographics.shape}")
        
        # Extraer y guardar datos de diagnóstico
        if df_clinical is not None:
            diag_cols = [col for col in df_clinical.columns if 'diagnoses' in col.lower()]
            if diag_cols:
                base_cols = ['case_id', 'patient_id'] if 'patient_id' in df_clinical.columns else ['case_id']
                base_cols = [col for col in base_cols if col in df_clinical.columns]
                df_diagnosis = df_clinical[base_cols + diag_cols].copy()
                
                output_file = OUTPUT_DIR / "tcga_brca_diagnosis.csv"
                df_diagnosis.to_csv(output_file, index=False)
                print(f"  ✓ Guardado: {output_file}")
                print(f"    Shape: {df_diagnosis.shape}")
        
        print(f"\n✓ Todos los archivos guardados en: {OUTPUT_DIR}")
        
    except Exception as e:
        print(f"  ✗ Error guardando archivos: {e}")
        import traceback
        traceback.print_exc()

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print("\nIniciando descarga de datos clínicos...\n")
    
    # 1. Obtener casos de TCGA-BRCA
    df_clinical = get_tcga_brca_cases()
    
    if df_clinical is None or df_clinical.empty:
        print("\n✗ No se pudieron obtener datos clínicos. Abortando.")
        return
    
    # 2. Procesar datos clínicos
    df_clinical = process_clinical_data(df_clinical)
    
    # 3. Extraer datos demográficos
    df_demographics = extract_demographics(df_clinical)
    
    # 4. Guardar archivos
    save_outputs(df_clinical, df_demographics)
    
    print("\n" + "="*80)
    print("   DESCARGA COMPLETADA")
    print("="*80)
    print(f"\nArchivos generados en: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()