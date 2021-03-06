#!/bin/bash
#
# releng-build-package - builds a Debian package (to be used in CI systems)
# Copyright (C) 2020 Eugenio "g7" Paolantonio <me@medesimo.eu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e

info() {
	echo "I: $@"
}

warning() {
	echo "W: $@" >&2
}

error() {
	echo "E: $@" >&2
	exit 1
}

[ -n "${CI}" ] || error "This script must run inside a CI environment!"

# Set some defaults. These can be specified in the CI build environment
[ -n "${RELENG_TAG_PREFIX}" ] || export RELENG_TAG_PREFIX="hybris-mobian/"
[ -n "${RELENG_BRANCH_PREFIX}" ] || export RELENG_BRANCH_PREFIX="feature/"
[ -n "${RELENG_FULL_BUILD}" ] || export RELENG_FULL_BUILD="no"

# There are three different "build types" that match the destination
# repository
# - feature-branch: this is meant only for testing purposes, a new
#   throwaway debian repository must be created by the receiver
# - staging: this comes from a push in the branch meant for production,
#   but still hasn't been tagged yet
# - production: this comes from a push in the branch meant for production,
#   and it has been also tagged.
#
# Default build type is "feature-branch", per-CI logic should determine
# which build type is by looking at available data.
# For how this script operates, "feature-branch" and "staging" are essentially
# the same: thus we're going to check only between "feature-branch" and "production".
BUILD_TYPE="feature-branch"
if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL}" == "true" ]; then
	# Travis CI

	COMMIT="${TRAVIS_COMMIT}"
	if [ -n "${TRAVIS_TAG}" ]; then
		TAG="${TRAVIS_TAG}"
		# Fetch the release name from the tag, and use that as comment,
		# appending the -production suffix
		COMMENT=$(echo "${TAG//${RELENG_TAG_PREFIX}/}" | cut -d "/" -f1).production
		BUILD_TYPE="production"
	else
		# Use the branch name as the comment, append -pr if it's a pull request
		COMMENT="${TRAVIS_BRANCH}"
		if [ "${TRAVIS_EVENT_TYPE}" == "pull_request" ]; then
			COMMENT="${COMMENT}.pull.request.test"
		fi
	fi
fi

# Build debian/changelog
info "Building changelog from git history"

ARGS="--commit ${COMMIT} --comment ${COMMENT} --tag-prefix ${RELENG_TAG_PREFIX} --branch-prefix ${RELENG_BRANCH_PREFIX}"
case "${BUILD_TYPE}" in
	"production")
		ARGS="${ARGS} --tag ${TAG}"
		;;
	"feature-branch")
		ARGS="${ARGS} --branch ${TRAVIS_BRANCH}"
		;;
esac
# NOTE: On Travis CI we're stuck to depth 50 unless we unshallow.
eval ./build_changelog.py "${ARGS}"

# TODO? Build arch checks?

# FIXME: handle non-native packages

# Install build dependencies
info "Installing build dependencies"

mk-build-deps --remove --install --tool "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes" debian/control

# Finally build the package
info "Building package"

ARGS="--no-lintian -d -sa --no-sign --jobs=$(nproc)"
if [ "${RELENG_FULL_BUILD}" == "yes" ]; then
	# Full build, build source,any,all
	ARGS="${ARGS} -F"
	# Note on the -F usage: debuild crashes trying to read a not existing
	# .changes files when building source packages without supplying the
	# old style arguments, so here we are. 
else
	# Build only arch-dependent packages
	ARGS="${ARGS} --build=any"
fi

eval debuild "${ARGS}"
