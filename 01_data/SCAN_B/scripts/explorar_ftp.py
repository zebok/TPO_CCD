"""Script temporal para listar archivos en el FTP de GEO"""
import ftplib
import ssl

# Configurar FTP
ftp_host = "ftp.ncbi.nlm.nih.gov"
ftp_path = "/geo/series/GSE96nnn/GSE96058/matrix/"

print(f"Conectando a {ftp_host}...")
print(f"Explorando: {ftp_path}\n")

try:
    # Crear contexto SSL sin verificación
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    ftp = ftplib.FTP(ftp_host)
    ftp.login()  # login anónimo
    ftp.cwd(ftp_path)

    print("Archivos disponibles:")
    print("-" * 80)
    files = ftp.nlst()
    for f in files:
        print(f"  {f}")

    ftp.quit()
    print("\n✓ Listado completado")

except Exception as e:
    print(f"✗ Error: {e}")
