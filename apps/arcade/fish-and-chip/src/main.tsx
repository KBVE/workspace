import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import App from './app/app';

const container = document.getElementById('fishchip');
if (!container) {
	throw new Error('#fishchip is missing from index.html; nothing to mount.');
}

createRoot(container).render(
	<StrictMode>
		<App />
	</StrictMode>,
);
