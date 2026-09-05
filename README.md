# Inception of Things

Ce dépôt contient les différentes parties du projet :

- `vm_base/` : machine virtuelle hôte utilisée pour travailler sans droits
  administrateur sur les postes de l'école ;
- `P1/` : première partie avec les machines K3s server et worker ;
- `en.subject.pdf` : sujet du projet.

Pour créer ou démarrer la machine hôte :

```bash
cd vm_base
./bin/vagrant up
```

Le mode d'emploi complet se trouve dans [`vm_base/README.md`](vm_base/README.md).
