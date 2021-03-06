# Copyright 2013-2018 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *


class Rapidjson(CMakePackage):
    """A fast JSON parser/generator for C++ with both SAX/DOM style API"""

    homepage = "http://rapidjson.org"
    url      = "https://github.com/Tencent/rapidjson/archive/v1.1.0.tar.gz"
    git      = "https://github.com/Tencent/rapidjson"

    # NOTE : tag master for time being (see Tencent/rapidjson/issues/1341)
    version('1.1.1', git = git, commit='66eb6067b10')

    version('1.1.0', 'badd12c511e081fec6c89c43a7027bce')
    version('1.0.2', '97cc60d01282a968474c97f60714828c')
    version('1.0.1', '48cc188df49617b859d13d31344a50b8')
    version('1.0.0', '08247fbfa464d7f15304285f04b4b228')

    def patch(self):
        # NOTE : workaround for build error with 'gcc@7:', see Tencent/rapidjson/issues/1372
        filter_file(r'-Werror', r'-Werror -Wno-implicit-fallthrough', 'CMakeLists.txt')
