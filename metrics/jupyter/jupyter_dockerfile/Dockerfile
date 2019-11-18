# Copyright (c) Jupyter Development Team.
# Copyright (c) 2019 Intel Corporation
# Distributed under the terms of the Modified BSD License.

FROM jupyter/r-notebook

USER $NB_UID

# Install items required to process the metrics R(markdown) files
# and render them as interactive plotly charts
RUN conda install --quiet --yes r-plotly r-gridextra r-ggpubr
