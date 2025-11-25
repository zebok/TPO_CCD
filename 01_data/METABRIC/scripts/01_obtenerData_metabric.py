"""
Script REAL para descargar datos de METABRIC desde cBioPortal API
Descarga: datos clínicos, expresión génica, y datos de pacientes
"""

import requests
import pandas as pd
import numpy as np
import os
import time
import json
from pathlib import Path

print("="*80)
print("   DESCARGA REAL DE DATOS: COHORTE METABRIC")
print("   Fuente: cBioPortal API (https://www.cbioportal.org)")
print("="*80)

# Configuración
CBIOPORTAL_API = "https://www.cbioportal.org/api"
STUDY_ID = "brca_metabric"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "outputs_API_DEMO"  # NUEVO DIRECTORIO para no sobreescribir
OUTPUT_DIR.mkdir(exist_ok=True)

# Genes de interés (puedes agregar más)
GENES_OF_INTEREST = [
    "ESR1", "PGR", "ERBB2", "MKI67", "TP53",
    "BRCA1", "BRCA2", "PIK3CA", "PTEN", "AKT1",
    "GATA3", "FOXA1", "CDH1", "RB1", "MAP3K1"
]

# Headers para la API
HEADERS = {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
}

# -----------------------------------------------------------------------------
# PASO 1: OBTENER METADATOS DEL ESTUDIO
# -----------------------------------------------------------------------------
def fetch_study_metadata():
    """Obtiene información general del estudio METABRIC"""
    endpoint = f"{CBIOPORTAL_API}/studies/{STUDY_ID}"
    print(f"\n[1/5] Consultando metadatos del estudio: {STUDY_ID}...")

    try:
        resp = requests.get(endpoint, headers=HEADERS)
        resp.raise_for_status()

        meta = resp.json()
        print(f"  ✓ Estudio: {meta['name']}")
        print(f"  ✓ Descripción: {meta.get('description', 'N/A')[:80]}...")
        print(f"  ✓ Casos: {meta.get('allSampleCount', 'N/A')}")

        return meta
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 2: OBTENER LISTA DE PACIENTES/MUESTRAS
# -----------------------------------------------------------------------------
def fetch_sample_list():
    """Obtiene la lista de todas las muestras del estudio"""
    endpoint = f"{CBIOPORTAL_API}/studies/{STUDY_ID}/samples"
    print(f"\n[2/5] Obteniendo lista de muestras...")

    try:
        resp = requests.get(endpoint, headers=HEADERS, params={'projection': 'DETAILED'})
        resp.raise_for_status()

        samples = resp.json()
        print(f"  ✓ Total de muestras: {len(samples)}")

        # Convertir a DataFrame
        df_samples = pd.DataFrame(samples)
        print(f"  ✓ Columnas disponibles: {list(df_samples.columns)}")

        return df_samples
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None

# -----------------------------------------------------------------------------
# PASO 3: OBTENER DATOS CLÍNICOS
# -----------------------------------------------------------------------------
def fetch_clinical_data():
    """Obtiene todos los datos clínicos de pacientes"""

    # 3.1: Datos clínicos de PACIENTES
    endpoint_patient = f"{CBIOPORTAL_API}/studies/{STUDY_ID}/clinical-data"
    print(f"\n[3/5] Descargando datos clínicos de pacientes...")

    try:
        params = {
            'clinicalDataType': 'PATIENT',
            'projection': 'DETAILED'
        }

        resp = requests.get(endpoint_patient, headers=HEADERS, params=params)
        resp.raise_for_status()

        clinical_patient = resp.json()
        print(f"  ✓ Registros clínicos (paciente): {len(clinical_patient)}")

        # Convertir a formato ancho (pivotear)
        df_clinical_patient = pd.DataFrame(clinical_patient)
        if not df_clinical_patient.empty:
            df_patient_wide = df_clinical_patient.pivot_table(
                index='patientId',
                columns='clinicalAttributeId',
                values='value',
                aggfunc='first'
            ).reset_index()
            df_patient_wide.rename(columns={'patientId': 'PATIENT_ID'}, inplace=True)
            print(f"  ✓ Columnas clínicas: {len(df_patient_wide.columns)}")
        else:
            df_patient_wide = pd.DataFrame()

        # 3.2: Datos clínicos de MUESTRAS
        print(f"\n  Descargando datos clínicos de muestras...")
        params['clinicalDataType'] = 'SAMPLE'

        resp = requests.get(endpoint_patient, headers=HEADERS, params=params)
        resp.raise_for_status()

        clinical_sample = resp.json()
        print(f"  ✓ Registros clínicos (muestra): {len(clinical_sample)}")

        df_clinical_sample = pd.DataFrame(clinical_sample)
        if not df_clinical_sample.empty:
            df_sample_wide = df_clinical_sample.pivot_table(
                index='patientId',
                columns='clinicalAttributeId',
                values='value',
                aggfunc='first'
            ).reset_index()
            df_sample_wide.rename(columns={'patientId': 'PATIENT_ID'}, inplace=True)
        else:
            df_sample_wide = pd.DataFrame()

        return df_patient_wide, df_sample_wide

    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None, None

# -----------------------------------------------------------------------------
# PASO 4: OBTENER DATOS DE EXPRESIÓN GÉNICA
# -----------------------------------------------------------------------------
def fetch_gene_expression(sample_ids):
    """Obtiene datos de expresión génica para genes específicos"""

    # Primero necesitamos obtener los molecular profile IDs
    endpoint_profiles = f"{CBIOPORTAL_API}/studies/{STUDY_ID}/molecular-profiles"
    print(f"\n[4/5] Identificando perfiles moleculares disponibles...")

    try:
        resp = requests.get(endpoint_profiles, headers=HEADERS)
        resp.raise_for_status()
        profiles = resp.json()

        # Buscar el perfil de expresión mRNA
        mrna_profile = None
        for profile in profiles:
            if 'mrna' in profile['molecularAlterationType'].lower() or \
               'rna' in profile['molecularAlterationType'].lower():
                mrna_profile = profile['molecularProfileId']
                print(f"  ✓ Perfil mRNA encontrado: {mrna_profile}")
                break

        if not mrna_profile:
            print(f"  ✗ No se encontró perfil de expresión mRNA")
            return None

        # Obtener IDs de genes (Entrez) - usando query params en lugar de fetch
        print(f"\n  Mapeando símbolos de genes a Entrez IDs...")
        endpoint_genes = f"{CBIOPORTAL_API}/genes"

        genes_info = []
        for gene_symbol in GENES_OF_INTEREST:
            try:
                resp = requests.get(f"{endpoint_genes}/{gene_symbol}", headers=HEADERS)
                if resp.status_code == 200:
                    genes_info.append(resp.json())
            except:
                print(f"    ⚠ Gen no encontrado: {gene_symbol}")
                continue

        if not genes_info:
            print(f"  ✗ No se encontraron genes")
            return None

        entrez_ids = [gene['entrezGeneId'] for gene in genes_info]
        gene_symbols = {gene['entrezGeneId']: gene['hugoGeneSymbol'] for gene in genes_info}
        print(f"  ✓ Genes mapeados: {len(entrez_ids)}")

        # Descargar datos de expresión
        print(f"\n  Descargando datos de expresión génica...")
        endpoint_expression = f"{CBIOPORTAL_API}/molecular-profiles/{mrna_profile}/molecular-data/fetch"

        # Limitar a primeras 500 muestras para la demo (puedes quitar esto)
        sample_ids_subset = sample_ids[:500] if len(sample_ids) > 500 else sample_ids

        payload = {
            "entrezGeneIds": entrez_ids,
            "sampleIds": sample_ids_subset
        }

        resp = requests.post(endpoint_expression, headers=HEADERS, json=payload)
        resp.raise_for_status()

        expression_data = resp.json()
        print(f"  ✓ Registros de expresión descargados: {len(expression_data)}")

        # Convertir a DataFrame en formato ancho (genes como columnas)
        df_expression = pd.DataFrame(expression_data)

        if not df_expression.empty:
            # Mapear entrezGeneId a símbolo
            df_expression['geneSymbol'] = df_expression['entrezGeneId'].map(gene_symbols)

            df_expression_wide = df_expression.pivot_table(
                index='sampleId',
                columns='geneSymbol',
                values='value',
                aggfunc='first'
            ).reset_index()

            # Extraer PATIENT_ID del sampleId (formato típico: MB-XXXX)
            df_expression_wide['PATIENT_ID'] = df_expression_wide['sampleId'].str.extract(r'(MB-\d+)', expand=False)
            df_expression_wide = df_expression_wide.drop('sampleId', axis=1)

            print(f"  ✓ Matriz de expresión: {df_expression_wide.shape}")
            return df_expression_wide

        return None

    except Exception as e:
        print(f"  ✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return None

# -----------------------------------------------------------------------------
# PASO 5: GUARDAR DATOS
# -----------------------------------------------------------------------------
def save_data(df_patient, df_sample, df_expression):
    """Guarda los datos descargados en archivos"""
    print(f"\n[5/5] Guardando datos descargados...")

    try:
        # Guardar datos clínicos de pacientes
        if df_patient is not None and not df_patient.empty:
            output_file = OUTPUT_DIR / "data_clinical_patient.txt"
            df_patient.to_csv(output_file, sep='\t', index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_patient.shape}")

        # Guardar datos clínicos de muestras
        if df_sample is not None and not df_sample.empty:
            output_file = OUTPUT_DIR / "data_clinical_sample.txt"
            df_sample.to_csv(output_file, sep='\t', index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_sample.shape}")

        # Guardar datos de expresión
        if df_expression is not None and not df_expression.empty:
            output_file = OUTPUT_DIR / "data_mRNA_expression.txt"
            df_expression.to_csv(output_file, sep='\t', index=False)
            print(f"  ✓ Guardado: {output_file}")
            print(f"    Shape: {df_expression.shape}")

        print(f"\n✓ Todos los archivos guardados en: {OUTPUT_DIR}")

    except Exception as e:
        print(f"  ✗ Error guardando archivos: {e}")

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print("\nIniciando descarga...")

    # 1. Obtener metadatos
    metadata = fetch_study_metadata()

    # 2. Obtener lista de muestras
    df_samples = fetch_sample_list()
    if df_samples is None:
        print("\n✗ No se pudo obtener la lista de muestras. Abortando.")
        return

    sample_ids = df_samples['sampleId'].tolist()

    # 3. Obtener datos clínicos
    df_patient, df_sample = fetch_clinical_data()

    # 4. Obtener expresión génica
    df_expression = fetch_gene_expression(sample_ids)

    # 5. Guardar todo
    save_data(df_patient, df_sample, df_expression)

    print("\n" + "="*80)
    print("   DESCARGA COMPLETADA")
    print("="*80)
    print(f"\nArchivos generados en: {OUTPUT_DIR}")
    print("\nNOTA: Este script descarga genes específicos de interés.")
    print("Para descargar TODOS los genes, modifica la lista GENES_OF_INTEREST")
    print("o implementa lógica para obtener todos los genes disponibles.")

if __name__ == "__main__":
    main()
