# Copyright 2013-2018 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *


class RInfluencer(RPackage):
    """Provides functionality to compute various node centrality measures on
    networks. Included are functions to compute betweenness centrality (by
    utilizing Madduri and Bader's SNAP library), implementations of Burt's
    constraint and effective network size (ENS) metrics, Borgatti's algorithm
    to identify key players, and Valente's bridging metric. On Unix systems,
    the betweenness, Key Players, and bridging implementations are parallelized
    with OpenMP, which may run faster on systems which have OpenMP
    configured."""

    homepage = "https://github.com/rcc-uchicago/influenceR"
    url      = "https://cran.r-project.org/src/contrib/influenceR_0.1.0.tar.gz"
    list_url = "https://cran.r-project.org/src/contrib/Archive/influenceR"

    version('0.1.0', '6c8b6decd78c341364b5811fb3050ba5')

    depends_on('r-igraph', type=('build', 'run'))
    depends_on('r-matrix', type=('build', 'run'))
