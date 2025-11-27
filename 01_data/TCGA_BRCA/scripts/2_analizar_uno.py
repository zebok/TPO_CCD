import google.generativeai as genai
from pypdf import PdfReader
import tkinter as tk
from tkinter import filedialog
import os

# --- 1. CONFIGURACIÓN ---
# ¡Pega tu API KEY aquí!
API_KEY = "AIzaSyAnMoYdOeffhvtPUoKOK7wp21fJo2uNnNw"
genai.configure(api_key=API_KEY)
model = genai.GenerativeModel("gemini-2.5-flash")

# --- 2. FUNCIÓN PARA LEER EL PDF (Ya no simulamos) ---
def extraer_texto_de_pdf(ruta_archivo):
    try:
        reader = PdfReader(ruta_archivo)
        texto_completo = ""
        # Leemos todas las páginas
        for pagina in reader.pages:
            texto_completo += pagina.extract_text() + "\n"
        return texto_completo
    except Exception as e:
        return f"Error leyendo PDF: {e}"

# --- 3. FUNCIÓN PARA HABLAR CON GEMINI (VERSIÓN EXTENDIDA) ---
def analizar_con_gemini(texto_medico):
    print("🤖 Analizando con IA (extracción completa)...")
    prompt = f"""
    Eres un experto en patología oncológica y extracción de datos clínicos.
    Analiza este reporte patológico y extrae TODA la información disponible.

    IMPORTANTE:
    - Devuelve SOLO JSON válido, sin texto adicional ni markdown
    - Si un campo no está presente, usa null
    - Normaliza valores (ej: "Grade III" → 3, "Positive" → "Positive")
    - Extrae el Patient ID en formato TCGA-XX-XXXX si está disponible

    Estructura JSON esperada:
    {{
        "patient_id": "TCGA-XX-XXXX o null",
        "specimen_id": "UUID del specimen si está disponible",
        "accession_number": "número de accesión del reporte",

        "diagnosis": {{
            "primary_diagnosis": "diagnóstico principal (ej: Invasive Ductal Carcinoma)",
            "histologic_type": "tipo histológico detallado",
            "grade": "grado tumoral como número (1, 2, 3) o null",
            "differentiation": "well/moderately/poorly differentiated o null"
        }},

        "tumor_characteristics": {{
            "size_cm": "tamaño máximo en cm (como número decimal) o null",
            "thickness_cm": "espesor en cm o null",
            "site": "sitio anatómico (ej: tongue, breast, tonsil)",
            "laterality": "right/left/bilateral o null"
        }},

        "biomarkers": {{
            "er_status": "Positive/Negative/null",
            "pr_status": "Positive/Negative/null",
            "her2_status": "Positive/Negative/null",
            "ki67_percentage": "porcentaje de Ki67 si está (número) o null"
        }},

        "staging": {{
            "tnm_t": "clasificación T (ej: T2)",
            "tnm_n": "clasificación N (ej: N0)",
            "tnm_m": "clasificación M (ej: M0)",
            "ajcc_stage": "estadio AJCC (ej: Stage II)",
            "pathologic_stage": "estadio patológico (pTNM)"
        }},

        "invasion": {{
            "perineural_invasion": "Present/Absent/null",
            "lymphovascular_invasion": "Present/Absent/null",
            "vascular_invasion": "Present/Absent/null",
            "bone_invasion": "Present/Absent/null"
        }},

        "lymph_nodes": {{
            "examined": "número de ganglios examinados (número entero) o null",
            "positive": "número de ganglios positivos (número entero) o null",
            "largest_metastasis_cm": "tamaño de la metástasis más grande en cm o null"
        }},

        "margins": {{
            "status": "negative/positive/close o null",
            "closest_margin_cm": "distancia del margen más cercano en cm o null",
            "involved_margin": "qué margen está involucrado (ej: lateral) o null"
        }},

        "additional_findings": {{
            "carcinoma_in_situ": "Present/Absent/null",
            "necrosis": "Present/Absent/null",
            "inflammation": "descripción o null",
            "other": "cualquier otro hallazgo relevante"
        }}
    }}

    TEXTO DEL REPORTE:
    {texto_medico[:15000]}
    """
    try:
        response = model.generate_content(prompt)
        texto_respuesta = response.text

        # Limpiar markdown si viene con ```json ... ```
        if "```json" in texto_respuesta:
            texto_respuesta = texto_respuesta.split("```json")[1].split("```")[0]
        elif "```" in texto_respuesta:
            texto_respuesta = texto_respuesta.split("```")[1].split("```")[0]

        return texto_respuesta.strip()
    except Exception as e:
        return f'{{"error": "Error de API: {e}"}}'

# --- 4. BLOQUE PRINCIPAL (SELECCIONAR ARCHIVO) ---
if __name__ == "__main__":
    # Esto oculta la ventanita principal de Tkinter que no necesitamos
    root = tk.Tk()
    root.withdraw()

    print("📂 Abriendo ventana para seleccionar archivo...")
    
    # Abre el explorador de archivos
    ruta_seleccionada = filedialog.askopenfilename(
        title="Selecciona un PDF médico",
        filetypes=[("Archivos PDF", "*.pdf")]
    )

    if ruta_seleccionada:
        print(f"📄 Archivo seleccionado: {os.path.basename(ruta_seleccionada)}")
        
        # 1. Sacamos el texto real del archivo
        texto_real = extraer_texto_de_pdf(ruta_seleccionada)
        
        # (Opcional) Imprimir un poquito para ver si leyó bien
        print(f"👀 Texto extraído (primeros 100 caracteres): {texto_real[:100]}...")
        print("-" * 30)

        # 2. Se lo mandamos a Gemini
        resultado_json = analizar_con_gemini(texto_real)

        print("\n" + "="*70)
        print("✅ RESULTADO FINAL (JSON ESTRUCTURADO)")
        print("="*70)
        print(resultado_json)

        # 3. Intentar formatear el JSON si es válido
        try:
            import json
            datos = json.loads(resultado_json)
            print("\n" + "="*70)
            print("📊 RESUMEN DE DATOS EXTRAÍDOS")
            print("="*70)
            print(f"Patient ID: {datos.get('patient_id', 'N/A')}")
            print(f"Diagnóstico: {datos.get('diagnosis', {}).get('primary_diagnosis', 'N/A')}")
            print(f"Grado: {datos.get('diagnosis', {}).get('grade', 'N/A')}")
            print(f"Tamaño: {datos.get('tumor_characteristics', {}).get('size_cm', 'N/A')} cm")
            print(f"ER: {datos.get('biomarkers', {}).get('er_status', 'N/A')}")
            print(f"PR: {datos.get('biomarkers', {}).get('pr_status', 'N/A')}")
            print(f"HER2: {datos.get('biomarkers', {}).get('her2_status', 'N/A')}")
            print(f"Estadio: {datos.get('staging', {}).get('ajcc_stage', 'N/A')}")
            print(f"Ganglios examinados: {datos.get('lymph_nodes', {}).get('examined', 'N/A')}")
            print(f"Ganglios positivos: {datos.get('lymph_nodes', {}).get('positive', 'N/A')}")
            print(f"Invasión perineural: {datos.get('invasion', {}).get('perineural_invasion', 'N/A')}")
            print(f"Invasión linfovascular: {datos.get('invasion', {}).get('lymphovascular_invasion', 'N/A')}")
            print("="*70)
        except json.JSONDecodeError:
            print("\n⚠️ El resultado no es JSON válido, pero se extrajo texto.")

    else:
        print("❌ No seleccionaste ningún archivo.")