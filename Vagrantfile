Vagrant.configure("2") do |config|
  # La box locale est forcee en AMD64 car Vagrant 2.3 ne comprend pas les
  # metadonnees d'architecture recentes de Vagrant Cloud.
  config.vm.box = "cloud-image/debian-13-vbox-amd64"
  config.vm.hostname = "iot"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "iot-host"

    vb.memory = 12288
    vb.cpus = 8

    # Autorise la virtualisation imbriquée
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    # Requis par VirtualBox pour exposer plusieurs processeurs au système invité.
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
  end

  # Exécute scripts/setup.sh lors du premier provisioning
  config.vm.provision "shell", path: "scripts/setup.sh"

  # Vérifie la configuration à chaque démarrage, après le setup initial.
  config.vm.provision "shell", path: "scripts/check-config.sh", run: "always"
end
