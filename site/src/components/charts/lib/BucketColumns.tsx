// Columns over the six delivery buckets, early to late, with a hairline at
// the promised date. Shared by F2 (share of orders) and F3 (1-2 star share).
// Which buckets are late, and which one is the promised date, come from
// charts.json delay_buckets.
import { scaleBand, scaleLinear } from "d3-scale";
import { motion } from "framer-motion";
import { useState } from "react";
import { charts } from "../../../data/charts";
import { ChartTooltip, type TipRow, type TipState } from "./Tooltip";
import { columnPath, growIn, PHONE_MAX, useDrawIn, useWidth } from "./chartKit";

export interface BucketDatum {
  bucket: string;
  value: number;
  tip: TipRow[];
}

interface Props {
  data: BucketDatum[];
  yLabel: string;
  xLabel: string;
  promisedLabel: string;
  format: (v: number) => string;
  /** Buckets whose value is printed on the column (selective labels). */
  labelled: string[];
}

const MAX_BAR = 24; // thin marks: never fill the band

export function BucketColumns({ data, yLabel, xLabel, promisedLabel, format, labelled }: Props) {
  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const cfg = charts.delay_buckets;
  const m = { top: 44, right: 4, bottom: 52, left: 40 };
  const innerW = Math.max(0, width - m.left - m.right);
  // Short bucket names when each bucket has less than 64px.
  const compact = innerW / Math.max(1, data.length) < 64;
  const height = width <= PHONE_MAX ? 250 : 280;
  const innerH = height - m.top - m.bottom;

  const x = scaleBand<string>().domain(data.map((d) => d.bucket)).range([0, innerW]).padding(0.2);
  const max = Math.max(...data.map((d) => d.value));
  const y = scaleLinear().domain([0, max]).nice(4).range([innerH, 0]);
  const bw = Math.min(MAX_BAR, x.bandwidth());
  const promiseX = (x(cfg.promise) ?? 0) + x.bandwidth() / 2;

  // Tick text: the full bucket name on wider charts, the short name on
  // phones; broken onto two lines at the last space.
  const tickLines = (b: string) => {
    const t = compact ? (cfg.short[b] ?? b) : b;
    const i = t.lastIndexOf(" ");
    return i > 0 ? [t.slice(0, i), t.slice(i + 1)] : [t];
  };

  return (
    <div ref={box} className="relative" onPointerLeave={() => setTip(null)}>
      {width > 0 && (
        <svg ref={ref} width={width} height={height} className="block overflow-visible">
          <g transform={`translate(${m.left},${m.top})`}>
            {/* gridlines + y ticks */}
            {y.ticks(4).map((t) => (
              <g key={t} transform={`translate(0,${y(t)})`}>
                <line x2={innerW} className="stroke-line" />
                <text x={-8} dy="0.32em" textAnchor="end" className="fill-muted text-[12px] tabular-nums">
                  {t}
                </text>
              </g>
            ))}
            <text x={-m.left} y={-30} className="fill-muted text-[12px]">
              {yLabel}
            </text>

            {/* promised date: a hairline through the middle of its bucket */}
            <line x1={promiseX} x2={promiseX} y1={0} y2={innerH} className="stroke-ink/50" />
            <text x={promiseX} y={-6} textAnchor="middle" className="fill-ink text-[12px]">
              {promisedLabel}
            </text>

            {data.map((d, i) => {
              const bx = (x(d.bucket) ?? 0) + (x.bandwidth() - bw) / 2;
              const late = cfg.late.includes(d.bucket);
              const active = tip?.title === d.bucket;
              return (
                <g key={d.bucket}>
                  <motion.path
                    d={columnPath(bx, y(d.value), bw, innerH)}
                    className={`${late ? "fill-late" : "fill-accent"} transition-opacity ${tip && !active ? "opacity-50" : ""}`}
                    {...growIn("y", drawn, instant, i * 0.07)}
                  />
                  {labelled.includes(d.bucket) && (
                    <motion.text
                      x={bx + bw / 2}
                      y={y(d.value) - 7}
                      textAnchor="middle"
                      className="fill-ink text-[12px] font-medium tabular-nums"
                      initial={instant ? false : { opacity: 0 }}
                      animate={{ opacity: drawn ? 1 : 0 }}
                      transition={{ duration: instant ? 0 : 0.4, delay: instant ? 0 : 0.5 + i * 0.07 }}
                    >
                      {format(d.value)}
                    </motion.text>
                  )}
                  {/* hit target: the whole band, taller than the mark */}
                  <rect
                    x={x(d.bucket)}
                    width={x.bandwidth()}
                    y={0}
                    height={innerH}
                    fill="transparent"
                    onPointerEnter={() =>
                      setTip({ x: m.left + bx + bw / 2, y: m.top + y(d.value), title: d.bucket, rows: d.tip })
                    }
                  />
                </g>
              );
            })}

            {/* baseline and bucket names */}
            <line x2={innerW} y1={innerH} y2={innerH} className="stroke-line-strong" />
            {data.map((d) => (
              <text
                key={d.bucket}
                x={(x(d.bucket) ?? 0) + x.bandwidth() / 2}
                y={innerH + 18}
                textAnchor="middle"
                className="fill-muted text-[12px]"
              >
                {tickLines(d.bucket).map((line, k) => (
                  <tspan key={k} x={(x(d.bucket) ?? 0) + x.bandwidth() / 2} dy={k === 0 ? 0 : 14}>
                    {line}
                  </tspan>
                ))}
              </text>
            ))}
          </g>
          <text x={m.left + innerW / 2} y={height - 2} textAnchor="middle" className="fill-muted text-[12px]">
            {xLabel}
          </text>
        </svg>
      )}
      <ChartTooltip tip={tip} width={width} />
    </div>
  );
}
