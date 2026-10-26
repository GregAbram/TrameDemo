#!/bin/bash
# install_trame_jupyter.sh -- one-time setup for running trame + ParaView
# (osmesa build) inside a TACC Analysis Portal (TAP) Jupyter session on
# Stampede3. Run it once from an ssh login; it is not sourced:
#
#   ./install_trame_jupyter.sh            # create/update everything
#   ./install_trame_jupyter.sh --fresh    # also rebuild the venv from scratch
#
# Settings below can be overridden with environment variables, e.g.
#   PV=/path/to/paraview-osmesa/6.1.1 ./install_trame_jupyter.sh
#
# It creates, under ${TRAME} (default ~/TRAME):
#   env.vars               settings used by the other files
#   trame_setup.sh         ParaView + venv environment (sourced by the kernel
#                          wrapper; source it yourself for a manual jupyter-lab)
#   trame_venv/            Python 3.12 venv: JupyterLab + trame-jupyter-extension,
#                          trame stack, ipykernel
#   pvpython-kernel.sh     Jupyter kernel wrapper around ParaView's pvpython
#   pv_kernel_launcher.py  run by the wrapper: venv on the path, then ipykernel
#   pv_kernel_check.py     starts the kernel headless and renders a cone
#   bin/jupyter-lab        runs the venv's JupyterLab; TAP finds it via PATH
#   trame_pv_cone.ipynb    example notebook (if not there already)
# plus the kernelspec ~/.local/share/jupyter/kernels/paraview-osmesa-<version>,
# and a marked block in ~/.bashrc that puts ${TRAME}/bin first on PATH.
# Existing env.vars / trame_setup.sh / kernel files are kept as *.bak.

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# ── Settings ────────────────────────────────────────────────────────────────
# ParaView osmesa install (must contain bin/pvpython) and the modules it needs
PV=${PV:-/work/01249/gda/stampede3/rpm-test/opt/apps/intel24/impi21/paraview-osmesa/6.1.1}
PV_MODULES=${PV_MODULES:-"intel/24.0 impi/21.11"}
# Python 3.12, to match ParaView's bundled CPython 3.12
PYTHON_MODULE=${PYTHON_MODULE:-python/3.12.11}
SYSPY=${SYSPY:-/opt/apps/python/3.12.11/bin/python3}
TRAME=${TRAME:-${HOME}/TRAME}

VENV=${TRAME}/trame_venv
PV_VERSION=$(basename "${PV}")
KERNEL_NAME=paraview-osmesa-${PV_VERSION}
KERNEL_DISPLAY="ParaView ${PV_VERSION} osmesa (pvpython + trame)"
KERNEL_DIR=${HOME}/.local/share/jupyter/kernels/${KERNEL_NAME}

for f in "${PV}/bin/pvpython" "${SYSPY}"; do
    [[ -e "$f" ]] || { echo "ERROR: missing $f (see Settings at the top of $0)"; exit 1; }
done

# Keep an active venv and stray paths out of the build
type deactivate &>/dev/null && deactivate
unset PYTHONPATH PYTHONHOME VIRTUAL_ENV
export PYTHONNOUSERSITE=1

mkdir -p "${TRAME}"

# Move an existing file aside before rewriting it
backup() {
    [[ -e "$1" ]] && mv -f "$1" "$1.bak" && echo "Kept old $1 as $1.bak"
    return 0
}

# ── env.vars ────────────────────────────────────────────────────────────────
backup "${TRAME}/env.vars"
cat > "${TRAME}/env.vars" <<EOF
export PV=${PV}
export PV_MODULES="${PV_MODULES}"
export PYTHON_MODULE=${PYTHON_MODULE}
export TRAME=${TRAME}
export VENV=${VENV}
EOF

# ── trame_setup.sh ──────────────────────────────────────────────────────────
backup "${TRAME}/trame_setup.sh"
cat > "${TRAME}/trame_setup.sh" <<'EOF'
# trame_setup.sh -- modules, ParaView and the trame venv. Sourced by
# pvpython-kernel.sh; source it yourself to run jupyter-lab by hand.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "trame_setup.sh: source this file, don't execute it"
    exit 1
fi

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/env.vars"

# Drop any active venv and stray PYTHONPATH
type deactivate &>/dev/null && deactivate
unset PYTHONPATH

module purge
[[ ":${MODULEPATH}:" == *:/opt/apps/modulefiles:* ]] || module use /opt/apps/modulefiles
module load ${PV_MODULES} ${PYTHON_MODULE}
export PATH="${PV}/bin:${PATH}"

source "${VENV}/bin/activate"
EOF

# ── venv ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--fresh" && -d "${VENV}" ]]; then
    echo "Removing ${VENV}"
    rm -rf "${VENV}"
fi

if [[ ! -x "${VENV}/bin/python" ]]; then
    echo "Creating ${VENV} with ${SYSPY}"
    "${SYSPY}" -m venv "${VENV}"
fi

PY="${VENV}/bin/python"
"${PY}" -m pip install --upgrade pip

# trame stack (versions tested with ParaView 6.1.1 on Stampede3, 2026-10)
"${PY}" -m pip install \
    trame==4.0.0 \
    trame-client==4.1.4 \
    trame-server==4.1.0 \
    trame-common==1.2.9 \
    trame-vtk==2.11.17 \
    trame-vuetify==3.3.0 \
    wslink==2.6.0 \
    aiohttp==3.14.5
# No numpy: ParaView bundles its own, and `import paraview` loads it before
# the venv is put on the path, so a venv numpy would never be used.

# Jupyter server TAP will run (found via `which jupyter-lab`) + kernel side
"${PY}" -m pip install \
    'jupyterlab==4.5.*' \
    trame-jupyter-extension==2.1.4 \
    ipykernel \
    ipywidgets==8.1.8

# The venv's own "python3" kernelspec would hide the user's usual python3
# kernel in every TAP session; without it, theirs (or Jupyter's built-in
# one) is used.
rm -rf "${VENV}/share/jupyter/kernels/python3"

# ── kernel launcher, wrapper + kernelspec ───────────────────────────────────
# PYTHONPATH can't be used for the venv: pvpython puts its own site-packages
# ahead of it, so ParaView's older typing_extensions breaks jupyter_client.
backup "${TRAME}/pv_kernel_launcher.py"
cat > "${TRAME}/pv_kernel_launcher.py" <<'EOF'
# Start ipykernel inside pvpython (run by pvpython-kernel.sh)
import runpy
import sys

import paraview.web.venv  # noqa: F401  $PV_VENV ahead of ParaView's bundled packages, like pvpython --venv

# pvpython swaps in VTK stream helpers without fileno(); ipykernel needs the real streams
for name in ("stdin", "stdout", "stderr"):
    real = getattr(sys, f"__{name}__", None)
    if real is not None:
        setattr(sys, name, real)

runpy.run_module("ipykernel_launcher", run_name="__main__", alter_sys=True)
EOF

backup "${TRAME}/pvpython-kernel.sh"
cat > "${TRAME}/pvpython-kernel.sh" <<EOF
#!/bin/bash
# Jupyter kernel: ParaView ${PV_VERSION} osmesa pvpython using ${VENV}
# (written by install_trame_jupyter.sh). Jupyter passes: -f <connection file>

# Modules + ParaView paths, so the kernel doesn't depend on the environment
# it was started from (TAP job, idev shell, ...)
source ${TRAME}/trame_setup.sh > /dev/null

# Keep ~/.local and stray paths out of the kernel
export PYTHONNOUSERSITE=1
unset PYTHONHOME PYTHONPATH
# Read by paraview.web.venv in the launcher
export PV_VENV=${VENV}

# OSMesa, not EGL: trame renders from another thread than the one that made
# the context, and Mesa EGL then fails (eglMakeCurrent 12290 = EGL_BAD_ACCESS)
export VTK_DEFAULT_OPENGL_WINDOW=vtkOSOpenGLRenderWindow

# Only if MPI_Init fails with "OFI EP enable failed":
# export I_MPI_FABRICS=shm

exec ${PV}/bin/pvpython ${TRAME}/pv_kernel_launcher.py "\$@"
EOF
chmod +x "${TRAME}/pvpython-kernel.sh"

mkdir -p "${KERNEL_DIR}"
cat > "${KERNEL_DIR}/kernel.json" <<EOF
{
 "argv": [
  "${TRAME}/pvpython-kernel.sh",
  "-f",
  "{connection_file}"
 ],
 "display_name": "${KERNEL_DISPLAY}",
 "language": "python",
 "metadata": {
  "debugger": false
 }
}
EOF

# ── jupyter-lab wrapper for TAP ─────────────────────────────────────────────
# TAP's job script runs `which jupyter-lab`. The job does not source
# ~/.bashrc; it inherits the environment TAP submitted it with, which is
# why ~/.bashrc puts ${TRAME}/bin first on PATH (below). Not exec: TAP checks
# `ps | grep <this path>` to see that Jupyter started.
mkdir -p "${TRAME}/bin"
cat > "${TRAME}/bin/jupyter-lab" <<EOF
#!/bin/bash
# jupyter-lab -> ${VENV} (written by install_trame_jupyter.sh)
unset PYTHONPATH PYTHONHOME
"${VENV}/bin/jupyter-lab" "\$@"
EOF
chmod +x "${TRAME}/bin/jupyter-lab"

# ── example notebook ────────────────────────────────────────────────────────
EXAMPLE="${SCRIPT_DIR}/examples/trame_pv_cone.ipynb"
if [[ -f "${EXAMPLE}" && ! -e "${TRAME}/trame_pv_cone.ipynb" ]]; then
    cp "${EXAMPLE}" "${TRAME}/trame_pv_cone.ipynb"
fi

# ── ~/.bashrc ───────────────────────────────────────────────────────────────
# Only adds ${TRAME}/bin to PATH (prints nothing, loads no modules), so other
# shells (scp, MPI ranks, batch jobs) are unaffected apart from jupyter-lab.
# Replaces an earlier marked block; the first run keeps ~/.bashrc.trame.bak.
BEGIN_MARK="# >>> trame TAP Jupyter (added by install_trame_jupyter.sh) >>>"
END_MARK="# <<< trame TAP Jupyter <<<"
BASHRC="${HOME}/.bashrc"
touch "${BASHRC}"
[[ -e "${BASHRC}.trame.bak" ]] || cp -p "${BASHRC}" "${BASHRC}.trame.bak"   # first run only
sed -i "/^${BEGIN_MARK}\$/,/^${END_MARK}\$/d" "${BASHRC}"
cat >> "${BASHRC}" <<EOF
${BEGIN_MARK}
export PATH="${TRAME}/bin:\${PATH}"
${END_MARK}
EOF

# ── Checks ──────────────────────────────────────────────────────────────────
JUPYTER="${VENV}/bin/jupyter"

echo
echo "== Installed in ${VENV}"
"${PY}" -m pip list 2>/dev/null | grep -iE '^(trame|wslink|aiohttp|jupyterlab|jupyter_server|jupyter-server|ipykernel|ipywidgets) '

echo
echo "== trame server extension (want: enabled, OK)"
"${JUPYTER}" server extension list 2>&1 | grep -iA1 trame || echo "WARNING: trame_jupyter_extension not listed"

echo
echo "== trame lab extension (want: enabled OK)"
"${JUPYTER}" labextension list 2>&1 | grep -i trame || echo "WARNING: trame-jupyter-extension not listed"

echo
echo "== Kernelspecs (want: ${KERNEL_NAME})"
"${JUPYTER}" kernelspec list

# Starts the kernel the way Jupyter does and renders a cone; rerun it on a
# compute node with:  ${VENV}/bin/python ${TRAME}/pv_kernel_check.py
cat > "${TRAME}/pv_kernel_check.py" <<EOF
# Start the ${KERNEL_NAME} kernel like Jupyter does and render a cone in it
from jupyter_client.manager import start_new_kernel

km, kc = start_new_kernel(kernel_name="${KERNEL_NAME}", startup_timeout=180)
try:
    code = r"""
import sys, trame
from paraview import simple
simple.Cone()
simple.Show()
view = simple.Render()
simple.SaveScreenshot("${TRAME}/pv_kernel_check.png", view)
print("OK", sys.executable, sys.version.split()[0], view.GetRenderWindow().GetClassName(), trame.__file__)
"""
    reply = kc.execute_interactive(code, timeout=120)
    print("status:", reply["content"]["status"])
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)
EOF

echo
echo "== Kernel check (want: OK .../pvpython 3.12.x vtkOSOpenGLRenderWindow .../trame_venv/..., status: ok)"
# Login/staff nodes: keep pvpython small (address-space limits) and give MPI
# its own OPX key (stale shared memory); harmless on compute nodes
if FI_OPX_UUID=$("${SYSPY}" -c 'import uuid;print(uuid.uuid4().hex)') \
   MALLOC_ARENA_MAX=2 LP_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
   "${PY}" -I "${TRAME}/pv_kernel_check.py"
then
    echo "Cone screenshot: ${TRAME}/pv_kernel_check.png"
else
    echo "WARNING: the ParaView kernel failed to start or run (see above)"
fi

cat <<EOF

== Done. ~/.bashrc now puts ${TRAME}/bin first on PATH (backup: ~/.bashrc.trame.bak).
Log out and back in, then submit a Jupyter job from TAP. Its output should say
   "using jupyter binary ${TRAME}/bin/jupyter-lab".
Open JupyterLab, open TRAME/trame_pv_cone.ipynb, and pick the kernel
   "${KERNEL_DISPLAY}".
EOF
