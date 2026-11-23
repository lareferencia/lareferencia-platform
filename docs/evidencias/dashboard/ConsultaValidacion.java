import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.lareferencia.backend.api.v5.*;
import org.lareferencia.backend.api.v5.ApiV5Dtos.*;
import org.lareferencia.backend.security.LocalAuthorizationService;
import org.lareferencia.core.domain.*;
import org.lareferencia.core.metadata.*;
import org.lareferencia.core.repository.jpa.*;
import org.lareferencia.core.repository.validation.*;
import org.lareferencia.core.service.validation.*;
import org.springframework.test.util.ReflectionTestUtils;
import static org.mockito.Mockito.*;

// Sonda de investigación. Ejecutar en un directorio temporal nuevo (ver el registro de evidencias).
class ConsultaValidacion {
    static final long ID = 4145;
    public static void main(String[] args) throws Exception {
        var directory = Files.createDirectory(Path.of(args[0]).resolve("datos"));
        var network = new Network();
        network.setAcronym("FIX");
        var snapshot = new NetworkSnapshot();
        snapshot.setNetwork(network);
        ReflectionTestUtils.setField(snapshot, "id", ID);
        var metadata = new SnapshotMetadata();
        metadata.setSnapshotId(ID);
        metadata.setNetwork(network);
        metadata.registerRule(7L, "Idioma", "", "ONE_OR_MORE", true);

        var databases = new ValidationDatabaseManager();
        ReflectionTestUtils.setField(databases, "basePath", directory.toString());
        try {
            databases.initializeSnapshot(metadata, List.of(7L));
            try (var conn = databases.getDataSource(ID).getConnection(); var sql = conn.createStatement()) {
                sql.executeUpdate("INSERT INTO record_validation (identifier_hash,identifier,is_valid,is_transformed,rule_7) VALUES ('a','oai:1',1,0,1),('b','oai:10',0,1,0)");
                sql.executeUpdate("INSERT INTO rule_occurrences (identifier_hash,rule_id,is_valid,occurrence_value) VALUES ('a',7,1,'es'),('b',7,0,'?')");
            }
            var records = new RecordValidationRepository();
            var occurrences = new RuleOccurrenceRepository();
            ReflectionTestUtils.setField(records, "dbManager", databases);
            ReflectionTestUtils.setField(occurrences, "dbManager", databases);
            var store = mock(ISnapshotStore.class);
            when(store.getSnapshotMetadata(ID)).thenReturn(metadata);
            var stats = new ValidationStatisticsSQLiteService();
            ReflectionTestUtils.setField(stats, "basePath", directory.toString());
            ReflectionTestUtils.setField(stats, "dbManager", databases);
            ReflectionTestUtils.setField(stats, "recordRepository", records);
            ReflectionTestUtils.setField(stats, "occurrenceRepository", occurrences);
            ReflectionTestUtils.setField(stats, "snapshotStore", store);

            var snapshots = mock(NetworkSnapshotRepository.class);
            when(snapshots.findById(ID)).thenReturn(java.util.Optional.of(snapshot));
            var auth = mock(LocalAuthorizationService.class);
            var compat = new ApiV5DashboardCompatibilityController(null, snapshots, stats, auth, null);
            var diagnostics = new ApiV5DiagnosticsController(new ApiV5DiagnosticsService(snapshots, null, stats, null, store, auth));
            var valid = new DiagnosticFilter(DiagnosticFilterField.VALID, DiagnosticFilterOperator.EQ, true);
            var query = new DiagnosticQuery(List.of(valid), 0, 25);
            System.out.println("compat is_valid=true: " + compat.records("FIX", ID, true, null, null, null, null, 0, 25, null).getTotalElements());
            System.out.println("compat is_transformed=true: " + compat.records("FIX", ID, null, true, null, null, null, 0, 25, null).getTotalElements());
            System.out.println("compat valid_rules=7: " + compat.records("FIX", ID, null, null, List.of("7"), null, null, 0, 25, null).getTotalElements());
            System.out.println("compat invalid_rules=7: " + compat.records("FIX", ID, null, null, null, List.of("7"), null, 0, 25, null).getTotalElements());
            System.out.println("v5 VALID=true resumen: " + diagnostics.summaryQuery(ID, query, null).size());
            System.out.println("v5 VALID=true registros: " + diagnostics.recordsQuery(ID, query, null).totalElements());
            System.out.println("v5 VALID=true frecuencias: " + diagnostics.occurrencesQuery(ID, 7L, query, null));
            for (var operator : DiagnosticFilterOperator.values()) {
                var identifier = new DiagnosticFilter(DiagnosticFilterField.IDENTIFIER, operator, "oai:1");
                System.out.println("v5 identificador " + operator + ": " + diagnostics.recordsQuery(ID, new DiagnosticQuery(List.of(identifier), 0, 25), null).totalElements());
            }
            metadata.registerRule(8L, "Nueva", "", "ALL", false);
            try {
                diagnostics.summaryQuery(ID, query, null);
                System.out.println("v5 regla posterior: consulta admitida");
            } catch (ApiV5Exception exception) {
                System.out.println("v5 regla posterior: " + exception.getStatus() + " " + exception.getMessage());
            }
        } finally {
            databases.cleanup();
        }
    }
}
