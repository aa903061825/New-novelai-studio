const navButtons = document.querySelectorAll('[data-page-target]');
const pages = document.querySelectorAll('[data-page]');
const crumbPage = document.querySelector('[data-current-page]');
const toast = document.querySelector('[data-toast]');
const toastText = document.querySelector('[data-toast-text]');

function setPage(pageName) {
  pages.forEach((page) => {
    page.classList.toggle('is-active', page.dataset.page === pageName);
  });

  navButtons.forEach((button) => {
    const isActive = button.dataset.pageTarget === pageName;
    button.classList.toggle('is-active', isActive);
    button.setAttribute('aria-current', isActive ? 'page' : 'false');
  });

  const activeButton = document.querySelector(`[data-page-target="${pageName}"]`);
  if (activeButton && crumbPage) {
    crumbPage.textContent = activeButton.querySelector('.nav-label').textContent;
  }
}

navButtons.forEach((button) => {
  button.addEventListener('click', () => setPage(button.dataset.pageTarget));
});

document.querySelectorAll('[data-selectable]').forEach((item) => {
  item.addEventListener('click', () => {
    const group = item.dataset.selectable;
    document.querySelectorAll(`[data-selectable="${group}"]`).forEach((candidate) => {
      candidate.classList.remove('is-selected');
      candidate.classList.remove('is-active');
    });
    item.classList.add(item.classList.contains('tab') ? 'is-active' : 'is-selected');
  });
});

document.querySelectorAll('[data-toast-trigger]').forEach((button) => {
  button.addEventListener('click', () => {
    toastText.textContent = button.dataset.toastTrigger;
    toast.classList.add('is-visible');
    window.clearTimeout(window.__novelStudioToastTimer);
    window.__novelStudioToastTimer = window.setTimeout(() => {
      toast.classList.remove('is-visible');
    }, 2600);
  });
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    toast.classList.remove('is-visible');
  }
});

setPage('workbench');
