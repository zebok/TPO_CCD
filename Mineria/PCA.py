# Paquetes que vamos a usar
library(dplyr)
library(ggplot2)
library(FactoMineR)
library(factoextra)
library(MASS)
library(tidyr)

# 1) Cargar datos ---------------------------------------------------------
bd <- read.csv(
  "C:/Users/Agus Mieres/Desktop/dataset_consolidado_final.csv",
  header = TRUE,
  stringsAsFactors = FALSE
)

# Mirar dimensiones y columnas
dim(bd)
head(bd)
str(bd)

# 2) Definir vectores de nombres de variables -------------------------

# Variables de expresión génica
genes_cols <- c(
  "esr1_expression",
  "pgr_expression",
  "erbb2_expression",
  "mki67_expression",
  "tp53_expression",
  "brca1_expression",
  "brca2_expression",
  "pik3ca_expression",
  "pten_expression",
  "akt1_expression"
)

# Variables de imagen (todas las que empiezan con estos prefijos)
imaging_cols <- names(bd)[grepl(
  "^(radius_|texture_|perimeter_|area_|smoothness_|compactness_|concavity_|concave_points_|symmetry_|fractal_dimension_)",
  names(bd)
)]

length(imaging_cols)
imaging_cols

# 3) Convertir variables categóricas a factor -----------------------------

bd <- bd %>%
  mutate(
    er_status         = factor(er_status),
    pr_status         = factor(pr_status),
    her2_status       = factor(her2_status),
    tumor_subtype     = factor(tumor_subtype),
    race              = factor(race),
    menopausal_state  = factor(menopausal_state),
    vital_status      = factor(vital_status),
    chemotherapy      = factor(chemotherapy),
    hormone_therapy   = factor(hormone_therapy),
    radiotherapy      = factor(radiotherapy),
    breast_surgery    = factor(breast_surgery),
    tumor_grade       = factor(tumor_grade),
    lymph_node_status = factor(lymph_node_status),
    tumor_stage       = factor(tumor_stage),
    gender            = factor(gender)
  )

# Chequear NAs en genes e imagen
colSums(is.na(bd[genes_cols]))
colSums(is.na(bd[imaging_cols]))

#Armamos un bd con los pacientes que tienen toda la info
# Subset con genes + info clínica mínima
bd_genes <- bd %>%
  dplyr::select(
    id_paciente,
    dplyr::all_of(genes_cols),
    tumor_subtype,
    er_status,
    her2_status
  )

# Contamos cuántos genes faltan por paciente
bd_genes$na_genes <- apply(bd_genes[genes_cols], 1, function(x) sum(is.na(x)))

# Miramos la distribución de NAs por fila
table(bd_genes$na_genes)

# Nos quedamos solo con pacientes que tienen TODOS los genes medidos
bd_genes_clean <- bd_genes %>%
  dplyr::filter(na_genes == 0) %>%   # ningún gen faltante
  dplyr::select(-na_genes)

# Chequeo rápido: ya no debería haber NAs en genes
colSums(is.na(bd_genes_clean[genes_cols]))
nrow(bd_genes_clean)

library(FactoMineR)
library(factoextra)

# 1) Matriz numérica de genes ------------------------------------------

X_genes <- bd_genes_clean[, genes_cols]

# 2) Estandarizar (media 0, varianza 1) -------------------------------

X_genes_scaled <- scale(X_genes)

# 3) PCA de genes ------------------------------------------------------

res_pca_genes <- PCA(X_genes_scaled, graph = FALSE)

# 4) Screeplot: varianza explicada por cada componente ---------------

fviz_screeplot(res_pca_genes, addlabels = TRUE,
               title = "PCA genes - Varianza explicada por componente")

# 5) Pacientes en el plano PC1–PC2, coloreados por subtipo tumoral -----

fviz_pca_ind(
  res_pca_genes,
  label = "none",
  habillage = bd_genes_clean$tumor_subtype,  # color por subtipo
  addEllipses = TRUE,
  ellipse.level = 0.95,
  title = "PCA genes - Pacientes coloreados por subtipo tumoral"
)

# 6) Pacientes coloreados por ER status -------------------------------

fviz_pca_ind(
  res_pca_genes,
  label = "none",
  habillage = bd_genes_clean$er_status,      # color por ER+
  addEllipses = TRUE,
  ellipse.level = 0.95,
  title = "PCA genes - Pacientes coloreados por ER status"
)

# Cargar/variables del PCA (genes)
loadings_genes <- as.data.frame(res_pca_genes$var$coord)
loadings_genes$gene <- rownames(loadings_genes)

# Ordenar por contribución a PC1 y PC2
loadings_PC1 <- loadings_genes[order(-abs(loadings_genes$Dim.1)), c("gene", "Dim.1")]
loadings_PC2 <- loadings_genes[order(-abs(loadings_genes$Dim.2)), c("gene", "Dim.2")]

loadings_PC1
loadings_PC2

fviz_pca_var(
  res_pca_genes,
  col.var = "contrib",
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
  repel = TRUE,
  title = "PCA genes - Contribución de cada gen a las componentes"
)

#-------------------------------------------------------------------------------------------
#PCA de imagen + clusters
library(dplyr)
library(FactoMineR)
library(factoextra)

# 1) Subset con imagen + info mínima -----------------------------------

bd_img <- bd %>%
  dplyr::select(
    id_paciente,
    dplyr::all_of(imaging_cols),
    tumor_subtype,
    er_status,
    her2_status
  )

# 2) Contar cuántas variables de imagen faltan por paciente ------------

bd_img$na_img <- apply(bd_img[imaging_cols], 1, function(x) sum(is.na(x)))

# Mirar la distribución de NAs
table(bd_img$na_img)

# 3) Nos quedamos con pacientes con TODAS las features de imagen -------

bd_img_clean <- bd_img %>%
  dplyr::filter(na_img == 0) %>%
  dplyr::select(-na_img)

# Chequeo rápido
colSums(is.na(bd_img_clean[imaging_cols]))
nrow(bd_img_clean)

# Matriz numérica de imagen
X_img <- bd_img_clean[, imaging_cols]

# Estandarizar
X_img_scaled <- scale(X_img)

# PCA de imagen
library(FactoMineR)
library(factoextra)

res_pca_img <- PCA(X_img_scaled, graph = FALSE)

# Screeplot: varianza explicada
fviz_screeplot(
  res_pca_img,
  addlabels = TRUE,
  title = "PCA imagen - Varianza explicada por componente"
)

# Pacientes en PC1–PC2 por subtipo
fviz_pca_ind(
  res_pca_img,
  label = "none",
  habillage = bd_img_clean$tumor_subtype,
  addEllipses = TRUE,
  ellipse.level = 0.95,
  title = "PCA imagen - Pacientes por subtipo tumoral"
)

# Pacientes en PC1–PC2 por ER status
fviz_pca_ind(
  res_pca_img,
  label = "none",
  habillage = bd_img_clean$er_status,
  addEllipses = TRUE,
  ellipse.level = 0.95,
  title = "PCA imagen - Pacientes por ER status"
)

# Variables (features de imagen)
fviz_pca_var(
  res_pca_img,
  col.var = "contrib",
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
  repel = TRUE,
  title = "PCA imagen - Contribución de cada feature"
)

