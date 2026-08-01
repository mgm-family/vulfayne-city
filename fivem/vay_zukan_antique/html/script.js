(() => {
	const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vay_zukan_antique';

	// Percent-based rects measured against the 1376x768 sheet.jpg artwork.
	// Reading order: row1 (col1..5), row2 (col1..5).
	const SLOT_RECTS = [
		{ left: 11.63, top: 36.33, width: 11.77, height: 21.09 },
		{ left: 27.83, top: 36.33, width: 11.85, height: 21.09 },
		{ left: 44.11, top: 36.33, width: 11.77, height: 21.09 },
		{ left: 60.32, top: 36.33, width: 11.85, height: 21.09 },
		{ left: 76.53, top: 36.33, width: 11.85, height: 21.09 },
		{ left: 11.63, top: 64.97, width: 11.77, height: 20.70 },
		{ left: 27.83, top: 64.97, width: 11.85, height: 20.70 },
		{ left: 44.11, top: 64.97, width: 11.77, height: 20.70 },
		{ left: 60.32, top: 64.97, width: 11.85, height: 20.70 },
		{ left: 76.53, top: 64.97, width: 11.85, height: 20.70 },
	];
	const PLAQUE_RECT = { left: 40.70, top: 8.85, width: 18.53, height: 5.99 };
	const FLIP_MS = 320;

	let sheets = [];
	let state = { Owned: {}, Claimed: {} };
	let activeSheetIndex = 0;
	let flipping = false;

	const bookEl = document.getElementById('book');
	const pageEl = document.getElementById('page');
	const titleEl = document.getElementById('sheet-title');
	const progressEl = document.getElementById('progress-line');
	const gridEl = document.getElementById('grid');
	const modalEl = document.getElementById('modal');
	const modalCardEl = document.getElementById('modal-card');
	const modalImageEl = document.getElementById('modal-image');
	const modalNameEl = document.getElementById('modal-name');
	const modalDescEl = document.getElementById('modal-desc');

	function postNui(endpoint, data) {
		fetch(`https://${resourceName}/${endpoint}`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json; charset=UTF-8' },
			body: JSON.stringify(data || {}),
		}).catch(() => {});
	}

	function isOwned(itemId) {
		return !!(state.Owned && state.Owned[itemId]);
	}
	function isClaimed(sheetIndex) {
		return !!(state.Claimed && state.Claimed[sheetIndex]);
	}
	function imagePath(itemId) {
		return `images/${itemId}.png`;
	}

	// --- build static DOM: title box + 10 slots, positioned once ---

	titleEl.style.left = PLAQUE_RECT.left + '%';
	titleEl.style.top = PLAQUE_RECT.top + '%';
	titleEl.style.width = PLAQUE_RECT.width + '%';
	titleEl.style.height = PLAQUE_RECT.height + '%';
	titleEl.innerHTML = '<div class="title-main"></div><div class="title-progress"></div>';
	const titleMainEl = titleEl.querySelector('.title-main');
	const titleProgressEl = titleEl.querySelector('.title-progress');

	const slotEls = SLOT_RECTS.map((rect) => {
		const el = document.createElement('div');
		el.className = 'slot';
		el.style.left = rect.left + '%';
		el.style.top = rect.top + '%';
		el.style.width = rect.width + '%';
		el.style.height = rect.height + '%';
		gridEl.appendChild(el);
		return el;
	});

	// --- rendering ---

	function renderSheet() {
		const sheet = sheets[activeSheetIndex];
		if (!sheet) return;

		titleMainEl.textContent = sheet.Name;

		let owned = 0;
		sheet.Items.forEach((item) => {
			if (isOwned(item.Id)) owned += 1;
		});
		const sheetNumber = activeSheetIndex + 1;

		if (owned >= sheet.Items.length) {
			titleProgressEl.textContent = isClaimed(sheetNumber)
				? `シート ${sheetNumber}/${sheets.length} ・ コンプリート（景品受取済み）`
				: `シート ${sheetNumber}/${sheets.length} ・ コンプリート！NPCに話しかけよう`;
		} else {
			titleProgressEl.textContent = `シート ${sheetNumber}/${sheets.length} ・ ${owned}/${sheet.Items.length} 個登録済み`;
		}
		progressEl.textContent = `${sheet.Name}（${sheetNumber} / ${sheets.length}）`;

		sheet.Items.forEach((item, i) => {
			const el = slotEls[i];
			if (!el) return;
			const owned = isOwned(item.Id);
			el.className = 'slot ' + (owned ? 'unlocked' : 'locked');
			el.innerHTML = '';
			if (owned) {
				const img = document.createElement('div');
				img.className = 'slot-image';
				img.style.backgroundImage = `url('${imagePath(item.Id)}')`;
				el.appendChild(img);
			} else {
				const mark = document.createElement('div');
				mark.className = 'slot-mark';
				mark.textContent = '？';
				el.appendChild(mark);
			}
			el.onclick = () => openModal(item, owned);
		});

		// hide unused slots if a sheet somehow has fewer than 10 items
		for (let i = sheet.Items.length; i < slotEls.length; i++) {
			slotEls[i].className = 'slot';
			slotEls[i].innerHTML = '';
			slotEls[i].onclick = null;
		}
	}

	function goToSheet(delta) {
		if (flipping || sheets.length === 0) return;
		flipping = true;
		const dir = delta > 0 ? 1 : -1;
		pageEl.style.transform = `rotateY(${-dir * 90}deg)`;
		setTimeout(() => {
			activeSheetIndex = (activeSheetIndex + delta + sheets.length) % sheets.length;
			renderSheet();
			pageEl.style.transition = 'none';
			pageEl.style.transform = `rotateY(${dir * 90}deg)`;
			// force reflow so the next transition actually animates
			void pageEl.offsetWidth;
			pageEl.style.transition = '';
			requestAnimationFrame(() => {
				pageEl.style.transform = 'rotateY(0deg)';
			});
			setTimeout(() => { flipping = false; }, FLIP_MS);
		}, FLIP_MS);
	}

	function openModal(item, owned) {
		if (owned) {
			modalImageEl.style.backgroundImage = `url('${imagePath(item.Id)}')`;
			modalNameEl.textContent = item.Name;
			modalDescEl.textContent = item.Description;
		} else {
			modalImageEl.style.backgroundImage = '';
			modalNameEl.textContent = '？？？';
			modalDescEl.textContent = 'まだ登録されていない。マップのどこかに隠されている。';
		}
		modalEl.classList.remove('hidden');
	}
	function closeModal() {
		modalEl.classList.add('hidden');
	}
	function closeBook() {
		bookEl.classList.add('hidden');
		closeModal();
		postNui('close');
	}
	function applyTheme(category) {
		if (!category) return;
		if (category.ThemeColor) document.documentElement.style.setProperty('--accent', category.ThemeColor);
		if (category.ThemeColorBright) document.documentElement.style.setProperty('--accent-bright', category.ThemeColorBright);
	}

	document.getElementById('close-button').addEventListener('click', closeBook);
	document.getElementById('modal-close').addEventListener('click', closeModal);
	document.getElementById('prev-button').addEventListener('click', () => goToSheet(-1));
	document.getElementById('next-button').addEventListener('click', () => goToSheet(1));
	modalEl.addEventListener('click', (e) => {
		if (!modalCardEl.contains(e.target)) closeModal();
	});
	document.addEventListener('keydown', (e) => {
		if (bookEl.classList.contains('hidden')) return;
		if (e.key === 'Escape') {
			if (!modalEl.classList.contains('hidden')) closeModal();
			else closeBook();
		} else if (e.key === 'ArrowLeft') {
			goToSheet(-1);
		} else if (e.key === 'ArrowRight') {
			goToSheet(1);
		}
	});

	window.addEventListener('message', (event) => {
		const payload = event.data;
		if (!payload || !payload.action) return;

		if (payload.action === 'open') {
			sheets = payload.sheets || [];
			state = payload.state || { Owned: {}, Claimed: {} };
			activeSheetIndex = 0;
			applyTheme(payload.category);
			pageEl.style.transform = 'rotateY(0deg)';
			renderSheet();
			bookEl.classList.remove('hidden');
		} else if (payload.action === 'close') {
			bookEl.classList.add('hidden');
			closeModal();
		} else if (payload.action === 'state') {
			state = payload.state || state;
			if (!bookEl.classList.contains('hidden')) {
				renderSheet();
			}
		}
	});
})();
