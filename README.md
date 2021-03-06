# About Pike Kernel for Jupyter

pike-kernel-jupyter is a Kernel for the Jupyter interactive computing tool. This kernel is written in 
Pike and speaks the Jupyter protocol. 

## Demo

See a ready-to-test demo using Binder at https://bitbucket.org/hww3/pike-binder-example

## Prerequisites:

zeromq - sometimes called libzmq (if you have jupyter installed, it's likely you already have this)

Public.ZeroMQ - a module that allows pike to speak ZeroMQ. Install it with the following command:

```
[sudo] pike -x monger --install Public.ZeroMQ
```

## To install:

```
PIKE_KERNEL_DIR=/path/to/pike-kernel-jupyter
PIKE_MODULE_PATH=$PIKE_MODULE_PATH:$PIKE_KERNEL_DIR/MODULES
export PIKE_MODULE_PATH
jupyter kernelspec install $PIKE_KERNEL_DIR
```

You can also install the contents of the MODULES directory into a location already in
your pike module path and omit the steps that add to the Pike module path.

## Using

Start jupyter using the following command:

```
jupyter notebook
```

You can activate the Pike kernel for a notebook by using the "Change Kernel" command from the 
"Kernel" menu and selecting "Pike 8". 

## To uninstall:

jupyter kernelspec remove pike-kernel

## TODO

- upstream hilfe changes
- better code completion (a hilfe improvement, actually)
- mechanism for automatically wrapping responses such as Image objects
- widgets
