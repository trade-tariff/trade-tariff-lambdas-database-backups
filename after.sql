-- This script refreshes all materialized views in the 'uk', 'xi', and 'public' schemas.
-- It dynamically determines the refresh order based on dependencies between materialized views
-- by parsing the view definitions to find references to other materialized views.
-- Dependencies are detected through text analysis of the view definition SQL.
-- If a refresh fails (e.g., due to locks or errors), it logs a notice and continues.

DO $$
DECLARE
    current_mv text;       -- Variable to hold the current materialized view name
    start_time timestamp;  -- Timestamp to track start time for each refresh
    duration interval;     -- Interval to calculate refresh duration
    formatted_duration text;  -- Human-readable duration string (e.g., '0.019 seconds')
    overall_start timestamp := clock_timestamp();  -- Overall script start time

    -- Enhanced tracking variables
    total_views integer := 0;
    current_view_num integer := 0;
    success_count integer := 0;
    failure_count integer := 0;
    failed_views text[] := '{}';
    view_sizes text;
BEGIN
    -- Optimize memory for materialized view operations
    PERFORM set_config('maintenance_work_mem', '2GB', true);

    -- Create temporary table to store the ordered list of materialized views
    -- This table is dropped automatically at the end of the transaction (ON COMMIT DROP).
    CREATE TEMP TABLE ordered_mvs (
        mv_name text,
        depth integer,
        row_num integer
    ) ON COMMIT DROP;

    -- Build dependency information by parsing materialized view definitions
    -- We look for textual references to other materialized views in the definition SQL
    -- This approach works because PostgreSQL stores the view definition as text
    -- and views that reference other views will contain those references in their SQL
    CREATE TEMP TABLE temp_deps AS
    SELECT dependent.schemaname || '.' || dependent.matviewname AS dependent_view,
           referenced.schemaname || '.' || referenced.matviewname AS referenced_view
    FROM pg_matviews dependent
    JOIN pg_matviews referenced ON referenced.schemaname IN ('uk', 'xi', 'public')
        AND dependent.schemaname IN ('uk', 'xi', 'public')
        AND dependent.matviewname != referenced.matviewname
    WHERE (
        -- Look for explicit schema.table references in the view definition
        dependent.definition ILIKE '%' || referenced.schemaname || '.' || referenced.matviewname || '%'
        -- Also look for unqualified table references (assuming same schema context)
        OR dependent.definition ILIKE '%' || referenced.matviewname || '%'
    );

    -- Use a recursive Common Table Expression (CTE) to build a dependency tree
    -- This determines the correct refresh order: base views first, then dependent views
    WITH RECURSIVE dep_tree AS (
        -- Base case: Views that don't depend on any other materialized views (depth 0)
        -- These are "leaf" views that only reference base tables, not other materialized views
        SELECT mv.schemaname || '.' || mv.matviewname AS mv_name,
               0 AS depth
        FROM pg_matviews mv
        WHERE mv.schemaname IN ('uk', 'xi', 'public')
        AND NOT EXISTS (
            -- Check if this view appears as a dependent in our dependency table
            SELECT 1 FROM temp_deps td
            WHERE td.dependent_view = mv.schemaname || '.' || mv.matviewname
        )

        UNION ALL

        -- Recursive case: Views that depend on views from previous levels
        -- Each level of dependency increases the depth by 1
        SELECT td.dependent_view AS mv_name,
               dt.depth + 1 AS depth
        FROM dep_tree dt
        JOIN temp_deps td ON td.referenced_view = dt.mv_name
        WHERE dt.depth < 10  -- Prevent infinite recursion (max 10 levels of dependencies)
    )
    -- Insert unique view names into the ordered table with proper depth-based ordering
    -- Views at lower depths (fewer dependencies) are refreshed first
    INSERT INTO ordered_mvs (mv_name, depth, row_num)
    SELECT mv_name,
           MIN(depth) as depth,  -- Use minimum depth if a view appears at multiple levels
           ROW_NUMBER() OVER (ORDER BY MIN(depth) ASC, mv_name) as row_num
    FROM dep_tree
    GROUP BY mv_name
    ORDER BY MIN(depth) ASC, mv_name;

    -- Get total count for progress tracking
    SELECT COUNT(*) INTO total_views FROM ordered_mvs;

    RAISE NOTICE '';
    RAISE NOTICE '====== MATERIALIZED VIEW REFRESH STARTING ======';
    RAISE NOTICE 'Total views to refresh: %', total_views;
    RAISE NOTICE 'Schemas included: uk, xi, public';
    RAISE NOTICE 'Dependency detection method: Text analysis of view definitions';
    RAISE NOTICE 'Dependency-ordered refresh started at: %', to_char(overall_start, 'YYYY-MM-DD HH24:MI:SS');
    RAISE NOTICE '=================================================';
    RAISE NOTICE '';

    -- Loop over the ordered views and refresh each one.
    FOR current_mv, current_view_num IN
        SELECT mv_name, row_num FROM ordered_mvs ORDER BY row_num
    LOOP
        start_time := clock_timestamp();

        -- Get estimated size info for context
        BEGIN
            SELECT pg_size_pretty(pg_total_relation_size(current_mv::regclass))
            INTO view_sizes;
        EXCEPTION WHEN others THEN
            view_sizes := 'unknown size';
        END;

        RAISE NOTICE '[%/%] Starting refresh of % (%) at %',
            current_view_num, total_views, current_mv, view_sizes,
            to_char(start_time, 'HH24:MI:SS');

        BEGIN
            -- Perform the refresh. Add 'CONCURRENTLY' if your views have qualifying UNIQUE indexes
            -- (uncomment and test; it allows reads during refresh but requires the view to be populated).
            -- EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY ' || current_mv || ' WITH DATA';
            EXECUTE 'REFRESH MATERIALIZED VIEW ' || current_mv || ' WITH DATA';

            duration := clock_timestamp() - start_time;
            formatted_duration := round(extract(epoch FROM duration)::numeric, 3)::text || ' seconds';
            success_count := success_count + 1;

            RAISE NOTICE '[%/%] ✓ Completed % in %',
                current_view_num, total_views, current_mv, formatted_duration;

        EXCEPTION WHEN OTHERS THEN
            -- If refresh fails, log the error via NOTICE and continue to the next view.
            duration := clock_timestamp() - start_time;
            formatted_duration := round(extract(epoch FROM duration)::numeric, 3)::text || ' seconds';
            failure_count := failure_count + 1;
            failed_views := array_append(failed_views, current_mv);

            RAISE NOTICE '[%/%] ✗ Failed %: % (in %)',
                current_view_num, total_views, current_mv, SQLERRM, formatted_duration;
            -- Note: No re-raise, so the loop continues.
        END;
    END LOOP;

    -- Final summary with comprehensive statistics
    duration := clock_timestamp() - overall_start;
    formatted_duration := round(extract(epoch FROM duration)::numeric, 3)::text || ' seconds';

    RAISE NOTICE '';
    RAISE NOTICE '====== MATERIALIZED VIEW REFRESH SUMMARY ======';
    RAISE NOTICE 'Total runtime: %', formatted_duration;
    RAISE NOTICE 'Successfully refreshed: % views', success_count;
    RAISE NOTICE 'Failed refreshes: % views', failure_count;
    RAISE NOTICE 'Success rate: %', round((success_count::numeric / total_views * 100), 1) || '%';

    IF failure_count > 0 THEN
        RAISE NOTICE 'Failed views: %', array_to_string(failed_views, ', ');
        RAISE WARNING 'Some materialized views failed to refresh. Check logs above for details.';
    ELSE
        RAISE NOTICE 'All materialized views refreshed successfully! 🎉';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '====== DEPENDENCY ANALYSIS ======';

    -- Debug: Show what dependencies are found by parsing view definitions
    RAISE NOTICE 'Dependencies found by parsing view definitions:';
    FOR current_mv IN
        SELECT dependent.schemaname || '.' || dependent.matviewname || ' likely depends on ' ||
               referenced.schemaname || '.' || referenced.matviewname as dep_info
        FROM pg_matviews dependent
        JOIN pg_matviews referenced ON referenced.schemaname IN ('uk', 'xi', 'public')
            AND dependent.schemaname IN ('uk', 'xi', 'public')
            AND dependent.matviewname != referenced.matviewname
        WHERE (
            dependent.definition ILIKE '%' || referenced.schemaname || '.' || referenced.matviewname || '%'
            OR dependent.definition ILIKE '%' || referenced.matviewname || '%'
        )
        ORDER BY dependent.schemaname, dependent.matviewname
        LIMIT 10  -- Show first 10 to avoid too much output
    LOOP
        RAISE NOTICE '  %', current_mv;
    END LOOP;

    -- Show the actual depth distribution
    RAISE NOTICE '';
    RAISE NOTICE 'Refresh order by dependency depth:';
    FOR current_mv IN
        SELECT 'Depth ' || depth || ': ' || COUNT(*) || ' views (' ||
               string_agg(mv_name, ', ' ORDER BY mv_name) || ')' as depth_info
        FROM ordered_mvs
        GROUP BY depth
        ORDER BY depth
    LOOP
        RAISE NOTICE '  %', current_mv;
    END LOOP;

    RAISE NOTICE '===============================================';
END $$;
