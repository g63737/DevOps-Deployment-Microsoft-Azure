# Utiliser une image officielle Python légère
FROM python:3.10-slim

# Définir le dossier de travail dans le conteneur
WORKDIR /app

# Copier uniquement les fichiers nécessaires
COPY requirements.txt app.py test_app.py /app/

RUN pip install -r requirements.txt
RUN python test_app.py

EXPOSE 5000

# Commande par défaut : exécute app.py
CMD ["python", "app.py"]
