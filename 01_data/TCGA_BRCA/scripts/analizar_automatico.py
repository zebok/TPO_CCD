import google.generativeai as genai
from pypdf import PdfReader
import os
import json
import pandas as pd
import time

# --- 1. CONFIGURACIÓN ---
# Pega tu API KEY aquí
API_KEY = "AIzaSyAnMoYdOeffhvtPUoKOK7wp21fJo2uNnNw" 
genai.configure(api_key=API_KEY)
model = genai.GenerativeModel("gemini-2.5-flash") 

# Archivo donde guardaremos todo el dataset unificado
ARCHIVO_SALIDA = "dataset_clinico_unificado.csv"
# La carpeta raíz donde empieza todo (tu script vive un nivel arriba de esta)
CARPETA_RAIZ = "./MANIFEST" 

# --- 2. FUNCIONES AUXILIARES ---
def extraer_texto_de_pdf(ruta_archivo):
    try:
        reader = PdfReader(ruta_archivo)
        texto = ""
        for pagina in reader.pages:
            texto += pagina.extract_text() + "\n"
        return texto
    except Exception as e:
        print(f"⚠️ Error leyendo {os.path.basename(ruta_archivo)}: {e}")
        return None

def analizar_con_gemini(texto_medico, nombre_archivo):
    prompt = f"""
    Eres un experto en extracción de datos oncológicos.
    Analiza el siguiente reporte patológico y extrae datos en JSON.
    
    REGLAS:
    1. 'grado': Convertir a número entero (ej. "Grade III" -> 3). Si no hay, null.
    2. 'tipo_cancer': Normalizar (ej. 'Invasive Lobular', 'Ductal', etc.).
    3. 'biomarcadores': Extraer ER, PR, HER2.
    
    JSON ESPERADO:
    {{
        "archivo_origen": "{nombre_archivo}",
        "tipo_cancer": "...",
        "grado_tumor": 0,
        "tamano_cm": 0.0,
        "er_status": "...",
        "pr_status": "...",
        "her2_status": "..."
    }}
    
    Solo JSON.
    --- REPORTE ---
    {texto_medico[:10000]}
    """
    try:
        response = model.generate_content(prompt)
        texto_limpio = response.text.replace("```json", "").replace("```", "").strip()
        return json.loads(texto_limpio)
    except Exception as e:
        print(f"❌ Error API en {nombre_archivo}: {e}")
        return None

# --- 3. EL CEREBRO DEL PROCESO ---
def procesar_estructura_recursiva(carpeta_raiz, archivo_csv):
    # A. Cargar historial para no repetir (SKIP)
    archivos_procesados = set()
    if os.path.exists(archivo_csv):
        try:
            df_existente = pd.read_csv(archivo_csv)
            # Asumimos que la columna 'archivo_origen' guarda el nombre del PDF
            archivos_procesados = set(df_existente['archivo_origen'].unique())
            print(f"🔄 Se encontraron {len(archivos_procesados)} archivos ya procesados. Se saltarán.")
        except:
            print("⚠️ El CSV existe pero no se pudo leer. Se empezará de cero (o backupéalo).")

    datos_nuevos = []
    contador_sesion = 0

    # B. Recorrer carpetas recursivamente (el "Crawler")
    print(f"📂 Explorando estructura en: {carpeta_raiz}...")
    
    for root, dirs, files in os.walk(carpeta_raiz):
        for archivo in files:
            if archivo.lower().endswith(".pdf"):
                
                # 1. Chequeo de salto (SKIP)
                if archivo in archivos_procesados:
                    # print(f"⏭️ Saltando {archivo} (Ya existe)") # Descomentar si quieres ver los saltos
                    continue
                
                # 2. Procesamiento
                ruta_completa = os.path.join(root, archivo)
                print(f"⚙️ Procesando: {archivo} ...")
                
                texto = extraer_texto_de_pdf(ruta_completa)
                if not texto: continue

                datos = analizar_con_gemini(texto, archivo)
                
                if datos:
                    datos_nuevos.append(datos)
                    archivos_procesados.add(archivo) # Lo marcamos como listo en memoria
                    contador_sesion += 1

                    # 3. Guardado Incremental (cada 5 archivos para no perder nada)
                    if len(datos_nuevos) >= 5:
                        df_batch = pd.DataFrame(datos_nuevos)
                        # Si el archivo no existe, escribir cabecera. Si existe, no (mode='a').
                        escribir_cabecera = not os.path.exists(archivo_csv)
                        df_batch.to_csv(archivo_csv, mode='a', header=escribir_cabecera, index=False)
                        print(f"💾 Guardado parcial de {len(datos_nuevos)} registros.")
                        datos_nuevos = [] # Limpiamos el buffer
                        time.sleep(2) # Respeto a la API

    # Guardar remanentes al final
    if datos_nuevos:
        df_batch = pd.DataFrame(datos_nuevos)
        escribir_cabecera = not os.path.exists(archivo_csv)
        df_batch.to_csv(archivo_csv, mode='a', header=escribir_cabecera, index=False)
        print(f"💾 Guardado final de {len(datos_nuevos)} registros.")

    print(f"\n✅ ¡Proceso finalizado! Se procesaron {contador_sesion} archivos nuevos esta sesión.")

# --- 4. EJECUCIÓN ---
if __name__ == "__main__":
    procesar_estructura_recursiva(CARPETA_RAIZ, ARCHIVO_SALIDA)