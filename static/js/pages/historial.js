(() => {
  const input      = document.getElementById('historialSearchInput');
  const grid       = document.getElementById('patientsGrid');
  const noResults  = document.getElementById('patientsNoResults');
  if (!input || !grid) return;

  const items = Array.from(grid.querySelectorAll('.patient-item'));

  input.addEventListener('input', (e) => {
    const term = (e.target.value || '').toLowerCase().trim();
    let visible = 0;
    items.forEach(item => {
      const show = !term || item.textContent.toLowerCase().includes(term);
      item.classList.toggle('hidden', !show);
      if (show) visible++;
    });
    if (noResults) noResults.classList.toggle('hidden', !(term && visible === 0));
  });
})();

function goToPatient(card) {
  const url = card.parentElement.dataset.url;

  if (!url) return;

  window.location.href = url;
}


function openPhotoUploader(event, patientId) {
  event.stopPropagation();

  const input = document.getElementById(`photo-input-${patientId}`);

  if (input) {
    input.click();
  }
}


async function uploadPatientPhoto(patientId, input) {

  const file = input.files[0];

  if (!file) return;

  const avatarDiv   = input.previousElementSibling;
  const img         = avatarDiv.querySelector('.pt-avatar-img');
  const overlayIcon = avatarDiv.querySelector('.pt-avatar-overlay i');

  const formData = new FormData();
  formData.append('photo', file);

  avatarDiv.classList.add('pt-avatar--loading');

  if (overlayIcon) {
    overlayIcon.className = 'fa-solid fa-spinner fa-spin';
  }

  try {

    const response = await fetch(
      `/patients/${patientId}/photo`,
      {
        method: 'POST',
        body: formData
      }
    );

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Error al subir la foto');
    }

    const imageUrl = `${data.photo_url}?t=${Date.now()}`;

    if (img) {

      img.src = imageUrl;

    } else {

      const newImg = document.createElement('img');

      newImg.className = 'pt-avatar-img';
      newImg.src = imageUrl;

      avatarDiv.prepend(newImg);
    }

  } catch (error) {

    alert(error.message || 'Error de conexión al subir la foto');

  } finally {

    avatarDiv.classList.remove('pt-avatar--loading');

    if (overlayIcon) {
      overlayIcon.className = 'fa-solid fa-camera';
    }

    input.value = '';
  }
}


window.goToPatient = goToPatient;
window.openPhotoUploader = openPhotoUploader;
window.uploadPatientPhoto = uploadPatientPhoto;
