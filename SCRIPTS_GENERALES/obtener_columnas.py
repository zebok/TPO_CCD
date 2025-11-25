#!/usr/bin/env python3
"""
Script para obtener todas las columnas del archivo gdc_casos_metadata.csv
"""

import csv
import os

def obtener_columnas_csv(ruta_archivo):
    """
    Lee un archivo CSV y retorna todas las columnas (headers)
    
    Args:
        ruta_archivo (str): Ruta al archivo CSV
        
    Returns:
        list: Lista con los nombres de todas las columnas
    """
    if not os.path.exists(ruta_archivo):
        print(f"Error: El archivo {ruta_archivo} no existe")
        return []
    
    try:
        with open(ruta_archivo, 'r', encoding='utf-8') as archivo:
            lector_csv = csv.reader(archivo)
            # Leer la primera línea que contiene los headers
            columnas = next(lector_csv)
            return columnas
    except Exception as e:
        print(f"Error al leer el archivo: {e}")
        return []

def guardar_columnas(columnas, archivo_salida):
    """
    Guarda la lista de columnas en un archivo de texto
    
    Args:
        columnas (list): Lista de nombres de columnas
        archivo_salida (str): Ruta del archivo donde guardar las columnas
    """
    try:
        with open(archivo_salida, 'w', encoding='utf-8') as archivo:
            archivo.write(f"Total de columnas: {len(columnas)}\n")
            archivo.write("=" * 80 + "\n\n")
            
            for i, columna in enumerate(columnas, 1):
                archivo.write(f"{i}. {columna}\n")
        
        print(f"✓ Columnas guardadas exitosamente en: {archivo_salida}")
    except Exception as e:
        print(f"Error al guardar el archivo: {e}")

def main():
    # Ruta del archivo de entrada
    archivo_entrada = "/Users/sebastianporini/Desktop/TPO_CCD/01_data/TCGA_BRCA/outputs/tcga_brca_consolidated.csv"
    
    # Ruta del archivo de salida
    archivo_salida = "/Users/sebastianporini/Desktop/TPO_CCD/lista_columnas_tcga_brca.txt"
    
    print("Leyendo archivo CSV...")
    columnas = obtener_columnas_csv(archivo_entrada)
    
    if columnas:
        print(f"\n✓ Se encontraron {len(columnas)} columnas")
        print("\nPrimeras 10 columnas:")
        for i, col in enumerate(columnas[:10], 1):
            print(f"  {i}. {col}")
        
        if len(columnas) > 10:
            print(f"  ... y {len(columnas) - 10} columnas más")
        
        # Guardar en archivo
        print(f"\nGuardando lista completa de columnas...")
        guardar_columnas(columnas, archivo_salida)
        
        # También mostrar en consola si se desea
        print(f"\n{'='*80}")
        print("LISTA COMPLETA DE COLUMNAS:")
        print('='*80)
        for i, col in enumerate(columnas, 1):
            print(f"{i}. {col}")
    else:
        print("No se pudieron obtener las columnas del archivo")

if __name__ == "__main__":
    main()
