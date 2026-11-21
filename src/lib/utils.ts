import { clsx, type ClassValue } from 'clsx'; import { twMerge } from 'tailwind-merge';
export const cn=(...v:ClassValue[])=>twMerge(clsx(v));
export const statusLabel=(s:string)=>s.replaceAll('_',' ').toLowerCase().replace(/^\w/,c=>c.toUpperCase());
export const dateLabel=(s:string)=>new Date(s).toLocaleDateString(undefined,{day:'numeric',month:'short',year:'numeric'});
