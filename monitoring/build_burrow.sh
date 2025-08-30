#!/bin/bash

# Verzeichnis für den Quellcode
SOURCE_DIR="Burrow"
# Image-Name und Tag
IMAGE_NAME="burrow"
IMAGE_TAG="1.9.4"

# Quellcode klonen und in den richtigen Tag wechseln
echo "Klone Burrow-Quellcode (v${IMAGE_TAG})..."
git clone https://github.com/linkedin/Burrow.git "${SOURCE_DIR}"
cd "${SOURCE_DIR}"
git checkout "v${IMAGE_TAG}"

# sarama-Version in go.mod auf v1.46.0 ändern
echo "Passe sarama-Version auf v1.46.0 an..."
sed -i 's|github.com/IBM/sarama v1.45.1|github.com/IBM/sarama v1.46.0|g' go.mod
#cat go.mod

# Docker-Image bauen (Docker wird die Abhängigkeiten selbst auflösen)
echo "Baue Docker-Image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

# Aufräumen: Quellcode-Verzeichnis löschen
echo "Räume auf..."
cd ..
rm -rf "${SOURCE_DIR}"

echo "Fertig! Image ${IMAGE_NAME}:${IMAGE_TAG} wurde erfolgreich gebaut."
