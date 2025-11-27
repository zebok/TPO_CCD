import google.generativeai as genai
from pypdf import PdfReader
import os
import json
import csv
import time
import re

# --- 1. CONFIGURACIÓN ---
API_KEY = "AIzaSyAnMoYdOeffhvtPUoKOK7wp21fJo2uNnNw"  # <--- ¡No olvides pegarla!
CARPETA_PDFS = "procesar_pdfs"  # Nombre de la carpeta con tus archivos
ARCHIVO_SALIDA = "resultado_final.csv"

genai.configure(api_key=API_KEY)
# Usamos tu modelo potente
model = genai.GenerativeModel("gemini-2.5-flash")

# --- 2. FUNCIONES DE AYUDA ---
def extraer_texto(ruta):
    try:
        reader = PdfReader(ruta)
        texto = ""
        for page in reader.pages:
            texto += page.extract_text() + "\n"
        return texto
    except:
        return ""

def limpiar_json(texto_ia):
    # A veces la IA devuelve ```json ... ```, esto lo limpia
    texto_ia = re.sub(r"```json", "", texto_ia)
    texto_ia = re.sub(r"```", "", texto_ia)
    return texto_ia.strip()

def analizar_pdf(texto, nombre_archivo):
    prompt = f"""
    Analiza este reporte médico. Extrae datos en JSON plano.
    Si un dato no está, usa null.
    Archivo: {nombre_archivo}
    
    {{
        "archivo": "{nombre_archivo}",
        "id_paciente": "...",
        "diagnostico": "...",
        "tamano_tumor_mm": "numerico o null",
        "estrogeno": "Positivo/Negativo/null",
        "progesterona": "Positivo/Negativo/null",
        "her2": "Positivo/Negativo/null"
    }}

    --- TEXTO ---
    {texto[:30000]} 
    """
    # Limitamos a 30k caracteres por seguridad, aunque Flash aguanta mucho más
    try:
        response = model.generate_content(prompt)
        return json.loads(limpiar_json(response.text))
    except Exception as e:
        print(f"⚠️ Error procesando {nombre_archivo}: {e}")
        return None

# --- 3. BUCLE PRINCIPAL ---
def main():
    archivos = [f for f in os.listdir(CARPETA_PDFS) if f.lower().endswith(".pdf")]
    total = len(archivos)
    print(f"🚀 Iniciando procesamiento de {total} archivos...")

    # Preparamos el CSV
    columnas = ["archivo", "id_paciente", "diagnostico", "tamano_tumor_mm", "estrogeno", "progesterona", "her2"]
    
    with open(ARCHIVO_SALIDA, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columnas)
        writer.writeheader()

        for i, archivo in enumerate(archivos):
            ruta_completa = os.path.join(CARPETA_PDFS, archivo)
            print(f"[{i+1}/{total}] Leyendo: {archivo}...", end="\r")

            # 1. Leer PDF
            texto_pdf = extraer_texto(ruta_completa)
            
            if not texto_pdf.strip():
                continue # Si el PDF está vacío o es pura imagen sin texto, saltar

            # 2. Consultar a Gemini
            datos = analizar_pdf(texto_pdf, archivo)

            if datos:
                # 3. Guardar en CSV
                writer.writerow(datos)
            
            # 4. Pausa de seguridad (Rate Limit)
            # La versión gratuita tiene límites por minuto. 
            # 4 segundos de espera asegura ~15 peticiones por minuto.
            time.sleep(4) 

    print(f"\n\n✅ ¡TERMINADO! Revisa el archivo: {ARCHIVO_SALIDA}")

if __name__ == "__main__":
    main()