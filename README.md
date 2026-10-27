# trame + ParaView in TAP Jupyter on Stampede3 and Lonestar6

This repo sets up interactive ParaView visualizations with
[trame](https://kitware.github.io/trame/), inside a Jupyter notebook started
from the [TACC Analysis Portal](https://tap.tacc.utexas.edu/) (TAP) on
Stampede3 or Lonestar6. ParaView renders on the compute node, using its headless (OSMesa)
build. The view streams to your browser through the notebook's own
connection, so you don't need X, VNC or any extra ports or tunnels.


## Quick start

1. ssh to Stampede3 or Lonestar6 and run the installer once (it takes a few minutes):

   ```bash
   git clone https://github.com/GregAbram/TrameDemo.git
   TrameDemo/install_trame_jupyter.sh
   ```

   On Lonestar6, also set `PV` (see [Lonestar6](#lonestar6)).

2. Log out and back in.
3. In TAP, submit a **Jupyter** job. Open it in **JupyterLab**.
4. Open `TRAME/trame_pv_cone.ipynb`. Choose the kernel
   **ParaView 6.1.1 osmesa (pvpython + trame)**, then run the cells.

You should see a cone you can rotate with the mouse.

## Requirements

- A Stampede3 or Lonestar6 account with access to TAP.
- The ParaView **osmesa** build. On Stampede3, the default is a test install that anyone can
  read, at
  `/work/01249/gda/stampede3/rpm-test/opt/apps/intel24/impi21/paraview-osmesa/6.1.1`.
  It needs the `intel/24.0` and `impi/21.11` modules. Once the
  `paraview-osmesa` module is installed system-wide, this README and the
  installer defaults will change to use it.
- A Python 3.12 to create the venv, to match ParaView's bundled Python. On
  Stampede3 that's `python/3.12.11` (`/opt/apps/python/3.12.11`); on
  Lonestar6 it's ParaView's own bundled Python.
- Internet access from the login node, for `pip`.

## What the installer does

`install_trame_jupyter.sh` creates `~/TRAME`:

| Path | Purpose |
|---|---|
| `trame_venv/` | Python 3.12 venv with JupyterLab 4.5, `trame-jupyter-extension`, the trame 4.0 stack and ipykernel. |
| `bin/jupyter-lab` | Runs the venv's JupyterLab. TAP finds it through `PATH`. |
| `pvpython-kernel.sh`, `pv_kernel_launcher.py` | Start a Jupyter kernel in ParaView's own `pvpython`, with the venv's packages available. |
| `trame_setup.sh`, `env.vars` | Modules, ParaView and venv environment. The kernel uses them; you can source `trame_setup.sh` yourself. |
| `pv_kernel_check.py`, `pv_kernel_check.png` | Self-test: starts the kernel without a browser and renders a cone. |
| `trame_pv_cone.ipynb` | The example notebook, copied from `examples/`. It's only copied if you don't already have one. |

It also creates two things outside `~/TRAME`:
- **A kernelspec** at `~/.local/share/jupyter/kernels/paraview-osmesa-6.1.1/`.
- **A marked block at the end of `~/.bashrc`.** It only puts `~/TRAME/bin`
  first on `PATH`; it prints nothing and loads no modules:

  ```bash
  # >>> trame TAP Jupyter (added by install_trame_jupyter.sh) >>>
  export PATH="/home1/.../TRAME/bin:${PATH}"
  # <<< trame TAP Jupyter <<<
  ```

The first run saves your previous `~/.bashrc` as `~/.bashrc.trame.bak`. You
can rerun the installer at any time: it updates everything in place.
`--fresh` rebuilds the venv from scratch.

### Settings

The defaults for each machine are in `hosts/<system>.env`. The installer
picks the file from the hostname: `<system>` is the part just before
`.tacc.utexas.edu`, so `login1.ls6.tacc.utexas.edu` uses `hosts/ls6.env`.
To support another machine, add a file for it. `HOST_ENV=/path/to/file.env`
picks a file explicitly. You can override any setting with an environment
variable:

| Variable | Stampede3 default | Lonestar6 default | Meaning |
|---|---|---|---|
| `PV` | the test install above | none: set it in `hosts/ls6.env` or the environment | ParaView osmesa install; must contain `bin/pvpython` |
| `PV_MODULES` | `intel/24.0 impi/21.11` | `gcc/13.2 impi/21.18` | modules ParaView needs at run time |
| `PYTHON_MODULE` | `python/3.12.11` | none | Python module; set it empty for none |
| `SYSPY` | `/opt/apps/python/3.12.11/bin/python3` | `${PV}/bin/python3.12` or `python3` | Python 3.12 used to create the venv |
| `TRAME` | `~/TRAME` | `~/TRAME` | where everything is installed |

```bash
PV=/path/to/paraview-osmesa/6.1.1 PV_MODULES="intel/24.0 impi/21.11" ./install_trame_jupyter.sh
```

### Lonestar6

Lonestar6 doesn't have a default ParaView install yet. Set `PV` in
`hosts/ls6.env`, or on the command line:

```bash
PV=/path/to/paraview-osmesa/6.1.1 TrameDemo/install_trame_jupyter.sh
```

The venv is created from ParaView's bundled Python. TAP runs `jupyter-lab`
from that venv without loading any modules, so the installer checks that this
Python runs without them. If it doesn't, set `SYSPY` to another Python 3.12.

Lonestar6 has AMD CPUs, so use a ParaView build made for Lonestar6. A
Stampede3 build compiled for AVX-512 fails there with an illegal-instruction
error. Also check the module names with `module spider gcc` and
`module spider impi`.

### Checking the install

The installer ends with these checks:
- **Installed packages:** the trame and Jupyter versions in the venv.
- **Extensions:** `trame_jupyter_extension` (server) and
  `trame-jupyter-extension` (lab) both show **enabled OK**.
- **Kernelspecs:** `paraview-osmesa-6.1.1` is listed.
- **Kernel check:** the last section should print
  `OK .../pvpython 3.12.x vtkOSOpenGLRenderWindow .../trame_venv/...`, then
  `status: ok`. `~/TRAME/pv_kernel_check.png` should show a cone.

After you log back in, this should print `~/TRAME/bin/jupyter-lab` and `4.5.x`:

```bash
which jupyter-lab && jupyter-lab --version
```

## Using it

### In TAP

1. Submit a Jupyter job. When it starts, the job output should include:

   ```
   TACC: using jupyter binary /home1/.../TRAME/bin/jupyter-lab
   TACC: WARNING - non-system python detected. Script may not behave as expected
   ```

   That warning is expected.
2. Open the session in **JupyterLab** (`/lab`). The trame extension doesn't
   load in the classic notebook UI.
3. Choose **Kernel → Change Kernel → ParaView 6.1.1 osmesa (pvpython + trame)**.

### Writing your own notebooks

Start from `examples/trame_pv_cone.ipynb`. The essential part:

```python
from paraview import simple
from trame.app import get_server
from trame.ui.vuetify3 import SinglePageLayout
from trame.widgets import paraview as pvw, vuetify3 as v3

server = get_server("pv", client_type="vue3")

simple.Show(simple.Cone())
view = simple.Render()
simple.ResetCamera()

with SinglePageLayout(server) as layout:
    with layout.content:
        with v3.VContainer(fluid=True, classes="pa-0 fill-height"):
            pv_view = pvw.VtkRemoteView(view, interactive_ratio=1)

await layout.display_cell(height=600)
```

- **`await layout.display_cell(height=...)`** starts the trame server in the
  kernel and shows the app. A bare `layout` expression also works, but only as
  the last *top-level* line of a cell. Inside an `if` or `with` block, it
  shows nothing.
- **Wrap the view in a `VContainer(... fill-height)`.** Without it, the view
  can end up 0 px tall.
- **Prefer `VtkRemoteView`.** It renders on the node and sends images, so it
  works for any size of data. `VtkLocalView` instead sends geometry to the
  browser, where vtk.js renders it.
- **After changing the pipeline,** call `pv_view.update()` to push a new
  frame.
- **`os.system(...)` output** goes to the Jupyter server log, not the
  notebook. Use `!cmd` or `print(...)`.
- **To start over, restart the kernel.** The trame server keeps running
  between cells.

### Mouse and trackpad

| Mouse | Mac trackpad | Action |
|---|---|---|
| Left-drag | Click and drag | rotate |
| Shift + left-drag, or middle-drag | Shift + click and drag | pan |
| Right-drag, scroll wheel, or Ctrl + left-drag | Two-finger scroll, or Ctrl + click and drag | zoom |

On a Mac, turning on three-finger drag (**System Settings → Accessibility →
Pointer Control → Trackpad Options**) makes rotating easier.

### Without TAP (idev + ssh tunnel)

In an `idev` session:

```bash
source ~/TRAME/trame_setup.sh
```

```bash
jupyter-lab --no-browser --ip=$(hostname -s) --port=8888
```

Then, on your laptop, replace `<node>` with the idev node's name:

```bash
ssh -N -L 8888:<node>:8888 <user>@login2.stampede3.tacc.utexas.edu   # or login2.ls6.tacc.utexas.edu
```

Then open `http://localhost:8888/lab?token=...`, using the token that
`jupyter-lab` printed.

## Side effects

- **`jupyter-lab`:** in your shells and in every TAP Jupyter session, it is
  now the venv's JupyterLab, with the trame extension. Other notebooks keep
  working.
- **The "Python 3" kernel:** the installer removes the venv's own `python3`
  kernel, so your usual `python3` kernel, if you have one in
  `~/.local/share/jupyter/kernels`, still shows up. Otherwise "Python 3" is
  the venv's Python. To add your own environment as a separate kernel:

  ```bash
  /path/to/your/env/bin/python -m ipykernel install --user --name my-env --display-name "Python (my env)"
  ```

- **Later `PATH` changes:** a `module load python` or `conda activate` later
  in a shell puts another `jupyter-lab` first on `PATH` in that shell. TAP
  isn't affected, as long as nothing after the marked block in `~/.bashrc`
  does that.

## How it works

Five details aren't obvious:

1. **TAP jobs don't read `~/.bashrc`.** TAP's job script runs
   `which jupyter-lab` with the environment the job was *submitted* with,
   which `~/.bashrc` set up on a login node. A hook that checks for the TAP
   job (`SLURM_JOB_NAME`) therefore never runs. That's why the installer puts
   a `jupyter-lab` wrapper first on `PATH` instead. The wrapper doesn't
   replace its own process with JupyterLab, because TAP checks `ps` for the
   wrapper's path.
2. **pvpython ignores `PYTHONPATH` order.** It puts its own `site-packages`
   ahead of `PYTHONPATH`, so ParaView's older bundled packages, such as
   `typing_extensions`, would be used instead of the venv's and break
   `jupyter_client`. The launcher imports `paraview.web.venv`, with `PV_VENV`
   set, which puts the venv first, as `pvpython --venv` does.
3. **pvpython replaces `sys.stdout`/`sys.stderr`** with VTK objects that have
   no `fileno()`, which ipykernel needs. The launcher restores the real
   streams.
4. **EGL can't render from trame's thread.** On compute nodes, VTK picks EGL
   rendering. trame renders from another thread than the one that created
   the EGL context, and Mesa EGL refuses that (`eglMakeCurrent: 12290`, i.e.
   `EGL_BAD_ACCESS`), leaving a black or empty view. The kernel forces OSMesa
   with `VTK_DEFAULT_OPENGL_WINDOW=vtkOSOpenGLRenderWindow`.
5. **There's no numpy in the venv.** ParaView bundles its own, and
   `import paraview` loads it first.

## Troubleshooting

| Symptom | Fix |
|---|---|
| The TAP output says `using jupyter binary /opt/apps/python/.../jupyter-lab` | `~/TRAME/bin` wasn't first on `PATH` when TAP submitted the job. Check the marked block in `~/.bashrc`, and that nothing after it puts another `jupyter-lab` first. Log out and back in, then resubmit. |
| A sad face with "localhost refused to connect" where the app should be | Same as above: the trame extension isn't loaded. The notebook's first cell prints `None None` in that case. |
| A blank or 0-px view | Wrap the view in `VContainer(fluid=True, classes="pa-0 fill-height")`. Use `display_cell(height=...)`. |
| A black view (`VtkRemoteView`) or background only (`VtkLocalView`), and the Jupyter log shows `vtkEGLRenderWindow ... eglMakeCurrent: 12290` | Check that `~/TRAME/pvpython-kernel.sh` exports `VTK_DEFAULT_OPENGL_WINDOW=vtkOSOpenGLRenderWindow`, then restart the kernel. |
| The kernel dies at start, and the log shows `OFI EP enable failed` | Uncomment `export I_MPI_FABRICS=shm` in `~/TRAME/pvpython-kernel.sh`. |
| The kernel is slow to start (`Nudge: attempt ...` in the log) | Normal the first time on a node: it loads modules and ParaView from `/work`. |
| The TAP job hangs after `got login node jupyter port` | One of TAP's ssh tunnels to the login nodes failed. That's a TACC-side problem; resubmit or open a ticket. |
| You need the logs | TAP's Jupyter log is `~/.jupyter/<node>.log`. Kernel errors go there too. |

To check the kernel on a compute node without a browser:

```bash
~/TRAME/trame_venv/bin/python ~/TRAME/pv_kernel_check.py
```

## Uninstall

1. Delete the `# >>> trame TAP Jupyter` block from `~/.bashrc`. Or, if you
   haven't changed `~/.bashrc` since installing, restore
   `~/.bashrc.trame.bak`.
2. Remove the files:

   ```bash
   rm -rf ~/TRAME ~/.local/share/jupyter/kernels/paraview-osmesa-6.1.1
   ```

## Tested versions

Tested on Stampede3 SKX compute nodes in TAP, October 2026: ParaView 6.1.1
osmesa (intel24/impi21), trame 4.0.0, trame-vtk 2.11.17, trame-vuetify
3.3.0, trame-jupyter-extension 2.1.4, JupyterLab 4.5.11, Python 3.12.11 for
the venv, and ParaView's bundled 3.12.7. Lonestar6 support is not tested yet.
