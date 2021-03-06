# Copyright 2013-2018 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *


class PyBiopython(PythonPackage):
    """A distributed collaborative effort to develop Python libraries and
       applications which address the needs of current and future work in
       bioinformatics.

    """
    homepage = "http://biopython.org/wiki/Main_Page"
    url      = "http://biopython.org/DIST/biopython-1.65.tar.gz"

    version('1.70', 'feff7a3e2777e43f9b13039b344e06ff')
    version('1.65', '143e7861ade85c0a8b5e2bbdd1da1f67')

    depends_on('py-numpy', type=('build', 'run'))
