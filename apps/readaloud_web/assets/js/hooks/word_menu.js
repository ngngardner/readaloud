// Long-press / right-click menu on word spans inside a text container.
// Dispatches a `word-action` CustomEvent on window when a menu action is chosen:
//   detail: { kind: "play", index: <wordIndex> }
// Consumers listen on window for the verbs they support.

const LONG_PRESS_MS = 500;
const MOVE_THRESHOLD_PX = 10;

const MENU_INNER_HTML = `
	<button
		data-word-menu-action="play"
		class="w-full px-3 py-2 text-sm hover:bg-base-300 flex items-center gap-2"
	>
		<span aria-hidden="true">▶</span>
		<span>Play from here</span>
	</button>
`;

export function attachWordMenu(container) {
	if (!container) return () => {};

	const menu = document.createElement("div");
	menu.className =
		"word-menu hidden fixed z-50 bg-base-200 border border-base-content/10 rounded-lg shadow-xl py-1 min-w-[160px] overflow-hidden";
	menu.innerHTML = MENU_INNER_HTML;
	document.body.appendChild(menu);

	let activeWord = null;
	let pressTimer = null;
	let pressStart = null;

	const onDocClick = (e) => {
		if (menu.contains(e.target)) return;
		close();
	};

	const open = (word, x, y) => {
		activeWord = word;
		menu.classList.remove("hidden");
		const rect = menu.getBoundingClientRect();
		const top = Math.max(8, y - rect.height - 12);
		const left = Math.max(
			8,
			Math.min(x - rect.width / 2, window.innerWidth - rect.width - 8),
		);
		menu.style.top = `${top}px`;
		menu.style.left = `${left}px`;
		// Defer attaching close listeners so the opening event itself doesn't trigger close.
		setTimeout(() => {
			document.addEventListener("click", onDocClick);
			document.addEventListener("touchstart", onDocClick, { passive: true });
		}, 0);
	};

	const close = () => {
		menu.classList.add("hidden");
		activeWord = null;
		document.removeEventListener("click", onDocClick);
		document.removeEventListener("touchstart", onDocClick);
	};

	menu.addEventListener("click", (e) => {
		const btn = e.target.closest("[data-word-menu-action]");
		if (!btn || !activeWord) return;
		const kind = btn.dataset.wordMenuAction;
		const index = Number.parseInt(activeWord.dataset.wordIndex, 10);
		window.dispatchEvent(
			new CustomEvent("word-action", { detail: { kind, index } }),
		);
		close();
	});

	const onContextMenu = (e) => {
		const word = e.target.closest("[data-word-index]");
		if (!word) return;
		e.preventDefault();
		open(word, e.clientX, e.clientY);
	};

	const cancelPress = () => {
		if (pressTimer) {
			clearTimeout(pressTimer);
			pressTimer = null;
		}
		pressStart = null;
	};

	const onTouchStart = (e) => {
		const word = e.target.closest("[data-word-index]");
		if (!word) return;
		const touch = e.touches[0];
		pressStart = { x: touch.clientX, y: touch.clientY };
		pressTimer = setTimeout(() => {
			pressTimer = null;
			open(word, pressStart.x, pressStart.y);
			pressStart = null;
		}, LONG_PRESS_MS);
	};

	const onTouchMove = (e) => {
		if (!pressStart || !e.touches[0]) return;
		const dx = Math.abs(e.touches[0].clientX - pressStart.x);
		const dy = Math.abs(e.touches[0].clientY - pressStart.y);
		if (dx > MOVE_THRESHOLD_PX || dy > MOVE_THRESHOLD_PX) cancelPress();
	};

	container.addEventListener("contextmenu", onContextMenu);
	container.addEventListener("touchstart", onTouchStart, { passive: true });
	container.addEventListener("touchmove", onTouchMove, { passive: true });
	container.addEventListener("touchend", cancelPress, { passive: true });
	container.addEventListener("touchcancel", cancelPress, { passive: true });

	return function cleanup() {
		cancelPress();
		close();
		container.removeEventListener("contextmenu", onContextMenu);
		container.removeEventListener("touchstart", onTouchStart);
		container.removeEventListener("touchmove", onTouchMove);
		container.removeEventListener("touchend", cancelPress);
		container.removeEventListener("touchcancel", cancelPress);
		menu.remove();
	};
}
