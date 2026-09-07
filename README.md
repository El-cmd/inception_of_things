# Inception of Things

Ce dépôt contient les différentes parties du projet :

- `p1/` : première partie avec les machines K3s server et worker ;
- `p2/` : deuxième partie avec K3s et trois applications ;
- `p3/` : troisième partie avec K3d, Argo CD et GitOps ;
- `vm_base/` : machine virtuelle hôte facultative pour les postes sans droits
  administrateur ;
- `en.subject.pdf` : sujet du projet.

Pour créer ou démarrer la machine hôte :

```bash
cd vm_base
./bin/vagrant up
```

Le mode d'emploi complet se trouve dans [`vm_base/README.md`](vm_base/README.md).
