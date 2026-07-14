(function () {
  const dashboard = document.querySelector("[data-dashboard]");
  if (!dashboard) return;

  const refreshButton = dashboard.querySelector("[data-refresh-button]");
  const pollingSelect = dashboard.querySelector("[data-polling-select]");
  const boardContainer = dashboard.querySelector("[data-board-container]");
  const lastUpdated = dashboard.querySelector("[data-last-updated]");
  const cardCount = dashboard.querySelector("[data-card-count]");
  const errorBanner = dashboard.querySelector("[data-error-banner]");
  let timer = null;

  function escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function statusKey(status) {
    return String(status || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
  }

  function cardMarkup(card) {
    const assignees = card.assignees && card.assignees.length ? card.assignees.join(", ") : "Unassigned";
    const tags = card.tags && card.tags.length
      ? `
        <span class="tag-row">
          <span class="card-icon">Tags:</span>
          <span class="tag-list">
            ${card.tags.map((tag) => `<span class="tag-badge tag-${escapeHtml(tag.kind)}">${escapeHtml(tag.label)}</span>`).join("")}
          </span>
        </span>
      `
      : "";

    return `
      <a class="work-card" href="${escapeHtml(card.url)}" target="_blank" rel="noreferrer">
        <strong>${escapeHtml(card.title)}</strong>
        <span class="card-line"><span class="card-icon">User</span> ${escapeHtml(assignees)}</span>
        ${tags}
        <span class="card-line"><span class="card-icon">Time</span> ${escapeHtml(card.last_active_label)}</span>
      </a>
    `;
  }

  function renderBoard(data) {
    if (!data.board_sections.length) {
      boardContainer.innerHTML = `
        <div class="empty-state">
          <h2>No cards match these filters</h2>
          <p>Change the assignee or board filter to see more cards.</p>
        </div>
      `;
      return;
    }

    boardContainer.innerHTML = data.board_sections
      .map((board) => `
        <section class="board-section">
          <div class="board-header">
            <h2>${escapeHtml(board.name)}</h2>
            <span class="badge text-bg-light">${board.count} cards</span>
          </div>
          <div class="status-grid">
            ${board.columns.map((column) => `
              <div class="status-column status-${escapeHtml(statusKey(column.name))}">
                <div class="status-header">
                  <span>${escapeHtml(column.name)}</span>
                  <span class="count">${column.count}</span>
                </div>
                <div class="card-stack">
                  ${column.cards.map(cardMarkup).join("")}
                </div>
              </div>
            `).join("")}
          </div>
        </section>
      `)
      .join("");
  }

  async function refreshBoard() {
    errorBanner.classList.add("d-none");
    refreshButton.disabled = true;

    const sprintTag = dashboard.dataset.sprintTag;
    const params = new URLSearchParams({
      assignee: dashboard.dataset.assignee,
      board: dashboard.dataset.board
    });

    try {
      const response = await fetch(`/api/sprints/${encodeURIComponent(sprintTag)}/cards?${params}`);
      if (!response.ok) throw new Error(`Refresh failed with ${response.status}`);

      const data = await response.json();
      renderBoard(data);
      lastUpdated.textContent = data.generated_at_label;
      cardCount.textContent = data.cards_count;
    } catch (error) {
      errorBanner.textContent = error.message;
      errorBanner.classList.remove("d-none");
    } finally {
      refreshButton.disabled = false;
    }
  }

  function updatePolling() {
    if (timer) clearInterval(timer);

    const interval = Number(pollingSelect.value);
    if (interval > 0) {
      timer = setInterval(refreshBoard, interval);
      refreshBoard();
    }
  }

  refreshButton.addEventListener("click", refreshBoard);
  pollingSelect.addEventListener("change", updatePolling);
})();
